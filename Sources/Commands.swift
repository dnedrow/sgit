import Foundation
import GitKit

/// Implementations of each sgit subcommand. Each method receives the remaining
/// arguments after the subcommand name.
enum Commands {
    // MARK: - init

    static func initialize(_ args: [String]) throws {
        var bare = false
        var pathArg: String?
        for arg in args {
            switch arg {
            case "--bare": bare = true
            default: pathArg = arg
            }
        }

        let path = URL(fileURLWithPath: pathArg ?? FileManager.default.currentDirectoryPath)
        let repo = try GKRepository.GKInitRepository(at: path, bare: bare)
        let kind = bare ? "bare repository" : "repository"
        Terminal.print("Initialized empty Git \(kind) in \(repo.gitDir.path)")
    }

    // MARK: - status

    static func status(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let status = try repo.status()

        switch try repo.head() {
        case .branch(let name):
            Terminal.print("On branch \(Terminal.style(name, .bold))")
        case .detached(let oid):
            Terminal.print("HEAD detached at \(String(oid.hex.prefix(7)))")
        }

        if status.isClean {
            Terminal.print("nothing to commit, working tree clean")
            return
        }

        if !status.staged.isEmpty {
            Terminal.print("\nChanges to be committed:")
            for entry in status.staged.sorted(by: { $0.path < $1.path }) {
                Terminal.print("  " + Terminal.style("\(label(entry.status)): \(entry.path)", .green))
            }
        }

        if !status.unstaged.isEmpty {
            Terminal.print("\nChanges not staged for commit:")
            for entry in status.unstaged.sorted(by: { $0.path < $1.path }) {
                Terminal.print("  " + Terminal.style("\(label(entry.status)): \(entry.path)", .red))
            }
        }

        if !status.untracked.isEmpty {
            Terminal.print("\nUntracked files:")
            for path in status.untracked.sorted() {
                Terminal.print("  " + Terminal.style(path, .red))
            }
        }
    }

    private static func label(_ status: GKDiffStatus) -> String {
        switch status {
        case .added: return "new file"
        case .deleted: return "deleted"
        case .modified: return "modified"
        case .renamed: return "renamed"
        case .copied: return "copied"
        case .typeChange: return "typechange"
        case .untracked: return "untracked"
        }
    }

    // MARK: - add

    static func add(_ args: [String]) throws {
        guard !args.isEmpty else { throw SGitError.missingArgument("nothing specified, nothing added (use 'sgit add <path>')") }
        let repo = try RepositoryLocator.openCurrent()

        if args.contains(".") || args.contains("-A") || args.contains("--all") {
            let status = try repo.status()
            let paths = status.untracked + status.unstaged.map(\.path)
            for path in Set(paths) {
                try repo.GKAdd(path: path)
            }
            Terminal.print("Staged \(Set(paths).count) file(s).")
            return
        }

        for path in args {
            try repo.GKAdd(path: path)
        }
    }

    // MARK: - rm (unstage)

    static func remove(_ args: [String]) throws {
        guard !args.isEmpty else { throw SGitError.missingArgument("no paths given to 'sgit rm'") }
        let repo = try RepositoryLocator.openCurrent()
        for path in args {
            try repo.GKRemove(path: path)
        }
    }

    // MARK: - commit

    static func commit(_ args: [String]) throws {
        var message: String?
        var index = 0
        while index < args.count {
            switch args[index] {
            case "-m", "--message":
                index += 1
                guard index < args.count else { throw SGitError.missingArgument("-m requires a message") }
                message = args[index]
            default:
                break
            }
            index += 1
        }

        guard let message, !message.isEmpty else {
            throw SGitError.missingArgument("commit message (use -m \"message\")")
        }

        let repo = try RepositoryLocator.openCurrent()
        let signature = IdentityProvider.signature(for: repo)
        let oid = try repo.GKCreateCommit(message: message, author: signature)

        let branch = (try? repo.head().branchName) ?? "HEAD"
        let summary = message.components(separatedBy: "\n").first ?? message
        Terminal.print("[\(branch) \(String(oid.hex.prefix(7)))] \(summary)")
    }

    // MARK: - log

    static func log(_ args: [String]) throws {
        var maxCount = 50
        var index = 0
        while index < args.count {
            switch args[index] {
            case "-n", "--max-count":
                index += 1
                guard index < args.count, let n = Int(args[index]) else {
                    throw SGitError.invalidArgument("-n requires a number")
                }
                maxCount = n
            case let arg where arg.hasPrefix("-") && Int(arg.dropFirst()) != nil:
                maxCount = Int(arg.dropFirst())!
            default:
                break
            }
            index += 1
        }

        let repo = try RepositoryLocator.openCurrent()
        let commits = try repo.log(from: nil, maxCount: maxCount)
        if commits.isEmpty {
            Terminal.print("No commits yet.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy Z"

        for commit in commits {
            Terminal.print(Terminal.style("commit \(commit.oid.hex)", .yellow))
            if commit.isMerge {
                let parents = commit.parentOIDs.map { String($0.hex.prefix(7)) }.joined(separator: " ")
                Terminal.print("Merge: \(parents)")
            }
            Terminal.print("Author: \(commit.author.name) <\(commit.author.email)>")
            Terminal.print("Date:   \(formatter.string(from: commit.author.time))")
            Terminal.print("")
            for line in commit.message.components(separatedBy: "\n") {
                Terminal.print("    \(line)")
            }
            Terminal.print("")
        }
    }

    // MARK: - branch

    static func branch(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()

        if args.isEmpty {
            let branches = try repo.branches()
            let current = try? repo.head().branchName
            if branches.isEmpty {
                Terminal.print("No branches yet.")
                return
            }
            for branch in branches.sorted(by: { $0.name < $1.name }) {
                if branch.name == current {
                    Terminal.print("* " + Terminal.style(branch.name, .green))
                } else {
                    Terminal.print("  \(branch.name)")
                }
            }
            return
        }

        switch args[0] {
        case "-d", "--delete":
            guard args.count >= 2 else { throw SGitError.missingArgument("branch name to delete") }
            try repo.GKDeleteBranch(name: args[1])
            Terminal.print("Deleted branch \(args[1]).")
        case "-m", "--move":
            guard args.count >= 3 else { throw SGitError.missingArgument("old and new branch names") }
            try repo.GKRenameBranch(from: args[1], to: args[2])
            Terminal.print("Renamed branch \(args[1]) to \(args[2]).")
        default:
            try repo.GKCreateBranch(name: args[0], target: nil)
            Terminal.print("Created branch \(args[0]).")
        }
    }

    // MARK: - checkout

    static func checkout(_ args: [String]) throws {
        guard let target = args.first else { throw SGitError.missingArgument("branch or commit to checkout") }
        let repo = try RepositoryLocator.openCurrent()

        // Try as a branch first; fall back to a commit OID.
        let branchNames = (try? repo.branches().map(\.name)) ?? []
        if branchNames.contains(target) {
            try repo.GKCheckout(branch: target)
            Terminal.print("Switched to branch '\(target)'")
        } else if let oid = GKObjectID(hex: target) {
            try repo.GKCheckout(commit: oid)
            Terminal.print("Note: switching to '\(String(target.prefix(7)))' (detached HEAD)")
        } else {
            throw SGitError.invalidArgument("'\(target)' is not a known branch or full commit hash")
        }
    }

    // MARK: - tag

    static func tag(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()

        if args.isEmpty {
            let tags = try repo.tags()
            for tag in tags.sorted(by: { $0.shortName < $1.shortName }) {
                Terminal.print(tag.shortName)
            }
            return
        }

        switch args[0] {
        case "-d", "--delete":
            guard args.count >= 2 else { throw SGitError.missingArgument("tag name to delete") }
            try repo.GKDeleteTag(name: args[1])
            Terminal.print("Deleted tag \(args[1]).")
        case "-a", "--annotate":
            guard args.count >= 2 else { throw SGitError.missingArgument("tag name") }
            let name = args[1]
            var message = ""
            if let mIndex = args.firstIndex(where: { $0 == "-m" || $0 == "--message" }), mIndex + 1 < args.count {
                message = args[mIndex + 1]
            }
            let signature = IdentityProvider.signature(for: repo)
            try repo.GKCreateAnnotatedTag(name: name, target: nil, tagger: signature, message: message)
            Terminal.print("Created annotated tag \(name).")
        default:
            try repo.GKCreateTag(name: args[0], target: nil)
            Terminal.print("Created tag \(args[0]).")
        }
    }

    // MARK: - diff

    static func diff(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let staged = args.contains("--staged") || args.contains("--cached")

        let diff: GKDiff
        if staged {
            diff = try repo.GKDiffStaged()
        } else {
            // Diff between the two most recent commits, if available.
            let commits = try repo.log(from: nil, maxCount: 2)
            guard commits.count == 2 else {
                Terminal.print("Need at least two commits to diff (try 'sgit diff --staged').")
                return
            }
            diff = try repo.GKComputeDiff(from: commits[1].oid, to: commits[0].oid)
        }

        printDiff(diff)
    }

    private static func printDiff(_ diff: GKDiff) {
        if diff.deltas.isEmpty {
            Terminal.print("No changes.")
            return
        }

        for delta in diff.deltas {
            let header = "diff --git a/\(delta.oldPath ?? delta.path) b/\(delta.newPath ?? delta.path)"
            Terminal.print(Terminal.style(header, .bold))
            Terminal.print(Terminal.style("--- a/\(delta.oldPath ?? "/dev/null")", .bold))
            Terminal.print(Terminal.style("+++ b/\(delta.newPath ?? "/dev/null")", .bold))

            for hunk in delta.hunks {
                Terminal.print(Terminal.style(hunk.header, .cyan))
                for line in hunk.lines {
                    let text = "\(line.origin.rawValue)\(line.content)"
                    switch line.origin {
                    case .addition: Terminal.print(Terminal.style(text, .green))
                    case .deletion: Terminal.print(Terminal.style(text, .red))
                    case .context: Terminal.print(text)
                    }
                }
            }
        }

        Terminal.print("\n\(diff.filesChanged) file(s) changed, \(diff.insertions) insertion(s)(+), \(diff.deletions) deletion(s)(-)")
    }

    // MARK: - merge

    static func merge(_ args: [String]) throws {
        guard let branch = args.first else { throw SGitError.missingArgument("branch to merge") }
        let repo = try RepositoryLocator.openCurrent()
        let signature = IdentityProvider.signature(for: repo)
        let oid = try repo.GKMerge(branch: branch, author: signature)
        Terminal.print("Merged '\(branch)' -> \(String(oid.hex.prefix(7)))")
    }

    // MARK: - reset

    static func reset(_ args: [String]) throws {
        var mode: GKResetMode = .mixed
        var target: String?
        for arg in args {
            switch arg {
            case "--soft": mode = .soft
            case "--mixed": mode = .mixed
            case "--hard": mode = .hard
            default: target = arg
            }
        }

        let repo = try RepositoryLocator.openCurrent()
        let oid: GKObjectID
        if let target, let parsed = GKObjectID(hex: target) {
            oid = parsed
        } else if target == nil {
            oid = try repo.GKHeadCommitOID()
        } else {
            throw SGitError.invalidArgument("reset target must be a full 40-character commit hash")
        }

        try repo.GKReset(to: oid, mode: mode)
        Terminal.print("HEAD is now at \(String(oid.hex.prefix(7)))")
    }

    // MARK: - stash

    static func stash(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let message = args.isEmpty ? nil : args.joined(separator: " ")
        let oid = try repo.GKStash(message: message)
        Terminal.print("Saved working directory state \(String(oid.hex.prefix(7)))")
    }

    // MARK: - remote

    static func remote(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()

        if args.isEmpty {
            for remote in repo.GKRemotes().sorted(by: { $0.name < $1.name }) {
                Terminal.print("\(remote.name)\t\(remote.url)")
            }
            return
        }

        switch args[0] {
        case "add":
            guard args.count >= 3 else { throw SGitError.missingArgument("remote add <name> <url>") }
            try repo.GKAddRemote(name: args[1], url: args[2])
            Terminal.print("Added remote \(args[1]).")
        case "remove", "rm":
            guard args.count >= 2 else { throw SGitError.missingArgument("remote remove <name>") }
            try repo.GKRemoveRemote(name: args[1])
            Terminal.print("Removed remote \(args[1]).")
        default:
            throw SGitError.invalidArgument("unknown remote subcommand '\(args[0])'")
        }
    }

    // MARK: - Network commands

    /// `clone <url> [path]`
    static func clone(_ args: [String]) throws {
        guard let url = args.first else { throw SGitError.missingArgument("clone <url> [directory]") }
        let directory = args.count >= 2 ? args[1] : TransportFactory.defaultDirectoryName(for: url)
        let destination = URL(fileURLWithPath: directory)
        try RemoteService.clone(url: url, into: destination)
        Terminal.print("Done.")
    }

    /// `fetch [remote|url]`
    static func fetch(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let (remoteName, url) = try resolveRemote(args.first, repo: repo)
        _ = try RemoteService.fetch(repo: repo, remoteName: remoteName, url: url)
    }

    /// `pull [remote|url]`
    static func pull(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let (remoteName, url) = try resolveRemote(args.first, repo: repo)
        try RemoteService.pull(repo: repo, remoteName: remoteName, url: url)
    }

    /// `push [remote|url] [branch]`
    static func push(_ args: [String]) throws {
        let repo = try RepositoryLocator.openCurrent()
        let (remoteName, url) = try resolveRemote(args.first, repo: repo)
        let branch = args.count >= 2 ? args[1] : (try repo.head().branchName ?? "main")
        try RemoteService.push(repo: repo, remoteName: remoteName, url: url, branch: branch)
    }

    /// Resolves an argument that may be a remote name or a literal URL into a
    /// (name, url) pair, defaulting to "origin".
    private static func resolveRemote(_ argument: String?, repo: GKRepository) throws -> (String, String) {
        let store = RepositoryStore(gitDir: repo.gitDir)

        // A value that looks like a URL is used directly.
        if let argument, looksLikeURL(argument) {
            return ("origin", argument)
        }

        let name = argument ?? "origin"
        guard let url = store.readRemoteURL(name: name) else {
            throw SGitError.missingArgument("no URL configured for remote '\(name)' (pass a URL explicitly)")
        }
        return (name, url)
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        value.contains("://") || value.hasPrefix("file:")
            || TransportFactory.isSCPLike(value)           // e.g. git@github.com:org/repo.git
            || value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("~")
    }
}
