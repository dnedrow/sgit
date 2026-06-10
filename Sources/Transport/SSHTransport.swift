import Foundation

/// A `GKTransport` for SSH remotes. Launches `ssh` and invokes the remote
/// `git-upload-pack` / `git-receive-pack`, speaking the protocol over the pipe.
///
/// Supports both URL forms:
///   - `ssh://[user@]host[:port]/path/to/repo.git`
///   - `[user@]host:path/to/repo.git` (scp-like)
final class GKSSHTransport: PipeTransport {
    init(user: String?, host: String, port: Int?, path: String, service: GitService) {
        let ssh = URL(fileURLWithPath: "/usr/bin/ssh")
        var args: [String] = []
        if let port { args += ["-p", String(port)] }
        args.append(user.map { "\($0)@\(host)" } ?? host)
        // Quote the remote path so spaces and special characters survive.
        args.append("\(service.commandName) '\(path)'")
        super.init(executable: ssh, arguments: args, service: service)
    }
}

/// A `GKTransport` for local repositories (a filesystem path or `file://` URL).
/// Invokes `git upload-pack` / `git receive-pack` against the local repo, using
/// the exact same wire protocol as the network transports.
final class GKLocalTransport: PipeTransport {
    init(path: String, service: GitService) {
        // `git <verb>` keeps us on PATH without hardcoding plumbing locations.
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let verb = service == .uploadPack ? "upload-pack" : "receive-pack"
        super.init(executable: git, arguments: [verb, path], service: service)
    }
}
