import Foundation
import GitKit

/// Builds the appropriate `GKTransport` for a given remote URL, supporting
/// HTTP(S), SSH (both `ssh://` and scp-like syntax), and local repositories.
enum TransportFactory {

    /// The classified target of a remote URL.
    enum Target: Equatable {
        case http(URL)
        case ssh(user: String?, host: String, port: Int?, path: String)
        case local(String)
    }

    /// Classifies a remote URL into a transport target. Pure and side-effect
    /// free so it can be unit-tested without opening any connection.
    static func classify(_ url: String) throws -> Target {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // HTTP(S)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let parsed = URL(string: trimmed) else {
                throw SGitError.invalidArgument("invalid URL: \(url)")
            }
            return .http(parsed)
        }

        // Explicit ssh:// URL
        if trimmed.hasPrefix("ssh://") {
            guard let parsed = URL(string: trimmed), let host = parsed.host else {
                throw SGitError.invalidArgument("invalid ssh URL: \(url)")
            }
            let path = parsed.path.isEmpty ? "/" : parsed.path
            return .ssh(user: parsed.user, host: host, port: parsed.port, path: path)
        }

        // file:// URL
        if trimmed.hasPrefix("file://") {
            return .local(String(trimmed.dropFirst("file://".count)))
        }

        // scp-like syntax: [user@]host:path
        // Recognized (per Git's rule) when a colon appears before any slash, e.g.
        // `git@github.com:lmigtech/consumer-mobile-app-ios.git`.
        if isSCPLike(trimmed) {
            let colon = trimmed.firstIndex(of: ":")!
            let hostPart = String(trimmed[trimmed.startIndex..<colon])
            let path = String(trimmed[trimmed.index(after: colon)...])
            let user: String?
            let host: String
            if let at = hostPart.firstIndex(of: "@") {
                user = String(hostPart[hostPart.startIndex..<at])
                host = String(hostPart[hostPart.index(after: at)...])
            } else {
                user = nil
                host = hostPart
            }
            return .ssh(user: user, host: host, port: nil, path: path)
        }

        // Otherwise treat as a local filesystem path.
        let expanded = (trimmed as NSString).expandingTildeInPath
        return .local(URL(fileURLWithPath: expanded).standardizedFileURL.path)
    }

    /// Returns true for scp-like SSH URLs (`[user@]host:path`): a colon that is
    /// not part of a scheme, with no slash appearing before it.
    static func isSCPLike(_ url: String) -> Bool {
        guard !url.hasPrefix("/"), !url.hasPrefix(".") else { return false }
        guard let colon = url.firstIndex(of: ":") else { return false }
        let beforeColon = url[url.startIndex..<colon]
        // A slash before the colon means it's a path (e.g. ./a:b or /a/b:c),
        // and an empty host is not valid.
        return !beforeColon.isEmpty && !beforeColon.contains("/")
    }

    /// Creates a transport for `url` speaking the requested `service`.
    static func makeTransport(for url: String, service: GitService) throws -> GKTransport {
        switch try classify(url) {
        case .http(let parsed):
            return GKHTTPTransport(url: parsed, service: service)
        case .ssh(let user, let host, let port, let path):
            return GKSSHTransport(user: user, host: host, port: port, path: path, service: service)
        case .local(let path):
            return GKLocalTransport(path: path, service: service)
        }
    }

    /// Derives a default destination directory name from a remote URL.
    static func defaultDirectoryName(for url: String) -> String {
        var name = url
        if let slash = name.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            name = String(name[name.index(after: slash)...])
        }
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        if name.hasSuffix("/") { name = String(name.dropLast()) }
        return name.isEmpty ? "repository" : name
    }
}
