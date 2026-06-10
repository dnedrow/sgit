import Foundation
import GitKit

/// A `GKTransport` for HTTP(S) remotes using Git's "smart HTTP" protocol.
///
/// Negotiation is stateless: `connect()` performs `GET /info/refs?service=…`,
/// while `fetch`/`push` POST to the `git-upload-pack` / `git-receive-pack`
/// endpoints. Basic authentication is sourced from the URL userinfo or from
/// `GIT_USERNAME`/`GIT_PASSWORD` (or a `GIT_TOKEN`) environment variables.
final class GKHTTPTransport: GKTransport {
    private let baseURL: URL
    private let service: GitService
    private let credentials: (user: String, password: String)?
    private var capabilities: [String] = []

    init(url: URL, service: GitService) {
        self.service = service

        // Extract and strip userinfo from the URL if present.
        var creds: (String, String)?
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let user = components?.user {
            creds = (user, components?.password ?? "")
            components?.user = nil
            components?.password = nil
        }
        let cleaned = components?.url ?? url

        // Fall back to environment-provided credentials.
        let env = ProcessInfo.processInfo.environment
        if creds == nil {
            if let token = env["GIT_TOKEN"] {
                creds = ("x-access-token", token)
            } else if let user = env["GIT_USERNAME"], let pass = env["GIT_PASSWORD"] {
                creds = (user, pass)
            }
        }

        self.credentials = creds
        // Normalize: drop a trailing slash so path joins are predictable.
        var string = cleaned.absoluteString
        if string.hasSuffix("/") { string.removeLast() }
        self.baseURL = URL(string: string) ?? cleaned
    }

    // MARK: - GKTransport

    func connect() throws -> GKRemoteAdvertisement {
        let url = URL(string: baseURL.absoluteString + "/info/refs?service=\(service.httpService)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        applyAuth(&request)

        let data = try perform(request)
        let advertisement = GitWireProtocol.parseAdvertisement(data)
        self.capabilities = advertisement.capabilities

        return GKRemoteAdvertisement(
            references: advertisement.references,
            capabilities: advertisement.capabilities,
            head: advertisement.head
        )
    }

    func fetch(wants: [GKObjectID], haves: [GKObjectID]) throws -> Data {
        let url = URL(string: baseURL.absoluteString + "/\(GitService.uploadPack.httpService)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-git-upload-pack-request", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-git-upload-pack-result", forHTTPHeaderField: "Accept")
        applyAuth(&request)
        request.httpBody = GitWireProtocol.buildUploadPackRequest(
            wants: wants, haves: haves, serverCapabilities: capabilities)

        let response = try perform(request)
        return try GitWireProtocol.extractPackfile(from: response)
    }

    func push(commands: [GKPushCommand], packData: Data) throws -> [GKPushResult] {
        let url = URL(string: baseURL.absoluteString + "/\(GitService.receivePack.httpService)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-git-receive-pack-request", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-git-receive-pack-result", forHTTPHeaderField: "Accept")
        applyAuth(&request)
        request.httpBody = GitWireProtocol.buildReceivePackRequest(
            commands: commands, packData: packData, serverCapabilities: capabilities)

        let response = try perform(request)
        return GitWireProtocol.parseReportStatus(response, commands: commands)
    }

    // MARK: - Helpers

    private func applyAuth(_ request: inout URLRequest) {
        guard let credentials else { return }
        let raw = "\(credentials.user):\(credentials.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    /// Performs a request synchronously (the CLI is blocking by nature).
    private func perform(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var failure: Error?
        var statusCode = 0

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { failure = error }
            if let http = response as? HTTPURLResponse { statusCode = http.statusCode }
            result = data
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let failure {
            throw SGitError.unsupported("network error: \(failure.localizedDescription)")
        }
        guard (200..<300).contains(statusCode) else {
            if statusCode == 401 || statusCode == 403 {
                throw SGitError.unsupported("authentication failed (HTTP \(statusCode)) — set GIT_USERNAME/GIT_PASSWORD or GIT_TOKEN")
            }
            throw SGitError.unsupported("server returned HTTP \(statusCode)")
        }
        guard let result else {
            throw SGitError.unsupported("empty response from server")
        }
        return result
    }
}
