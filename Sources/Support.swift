import Foundation
import GitKit

/// Errors raised by the sgit command layer (distinct from GitKit's `GKError`).
enum SGitError: Error, CustomStringConvertible {
    case notARepository
    case missingArgument(String)
    case invalidArgument(String)
    case unsupported(String)

    var description: String {
        switch self {
        case .notARepository:
            return "not a git repository (or any of the parent directories): .git"
        case .missingArgument(let detail):
            return "missing argument: \(detail)"
        case .invalidArgument(let detail):
            return "invalid argument: \(detail)"
        case .unsupported(let detail):
            return detail
        }
    }
}

/// Utilities for resolving the working repository and the committer identity.
enum RepositoryLocator {
    /// Walks up from `start` looking for a directory containing a `.git` folder.
    static func discover(from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL? {
        let fm = FileManager.default
        // Use the true physical path (resolving e.g. /tmp -> /private/tmp on macOS)
        // so the working directory matches what GitKit's filesystem enumerators yield.
        var current = canonicalize(start)

        while true {
            let gitDir = current.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitDir.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil } // reached filesystem root
            current = parent
        }
    }

    /// Opens the repository containing the current working directory.
    static func openCurrent() throws -> GKRepository {
        guard let root = discover() else { throw SGitError.notARepository }
        return try GKRepository(at: root)
    }

    /// Returns the canonical physical path for a URL, resolving all symlinks.
    /// Falls back to the standardized URL if the path does not yet exist.
    private static func canonicalize(_ url: URL) -> URL {
        if let resolved = realpath(url.path, nil) {
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
        return url.standardizedFileURL
    }
}

/// Resolves the author/committer identity from environment and git config.
enum IdentityProvider {
    /// Builds a signature for the current commit, honoring env vars, repo config, then global config.
    static func signature(for repo: GKRepository) -> GKSignature {
        let env = ProcessInfo.processInfo.environment

        let name = env["GIT_AUTHOR_NAME"]
            ?? configValue("user.name", repo: repo)
            ?? NSUserName()

        let email = env["GIT_AUTHOR_EMAIL"]
            ?? configValue("user.email", repo: repo)
            ?? "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"

        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60
        return GKSignature(name: name, email: email, time: Date(), timeZoneOffset: offsetMinutes)
    }

    /// Reads a config key, preferring the repository config and falling back to `~/.gitconfig`.
    private static func configValue(_ key: String, repo: GKRepository) -> String? {
        let repoConfigURL = repo.gitDir.appendingPathComponent("config")
        if let config = try? GKConfiguration(from: repoConfigURL),
           let value = config.getString(key), !value.isEmpty {
            return value
        }

        let globalURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig")
        if let config = try? GKConfiguration(from: globalURL),
           let value = config.getString(key), !value.isEmpty {
            return value
        }

        return nil
    }
}
