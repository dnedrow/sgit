import Foundation
import GitKit

/// Top-level command router for the sgit CLI.
enum SGit {
    static let version = "1.0.0"

    /// Parses arguments and dispatches to the matching command.
    static func run(_ arguments: [String]) -> Int32 {
        // arguments[0] is the executable path; drop it.
        let args = Array(arguments.dropFirst())

        guard let command = args.first else {
            printHelp()
            return 0
        }

        let rest = Array(args.dropFirst())

        do {
            switch command {
            case "help", "--help", "-h":
                printHelp()
            case "version", "--version", "-v":
                Terminal.print("sgit version \(version) (GitKit \(GK.version))")
            case "init":
                try Commands.initialize(rest)
            case "status", "st":
                try Commands.status(rest)
            case "add":
                try Commands.add(rest)
            case "rm":
                try Commands.remove(rest)
            case "commit":
                try Commands.commit(rest)
            case "log":
                try Commands.log(rest)
            case "branch":
                try Commands.branch(rest)
            case "checkout", "switch":
                try Commands.checkout(rest)
            case "tag":
                try Commands.tag(rest)
            case "diff":
                try Commands.diff(rest)
            case "merge":
                try Commands.merge(rest)
            case "reset":
                try Commands.reset(rest)
            case "stash":
                try Commands.stash(rest)
            case "remote":
                try Commands.remote(rest)
            case "clone", "fetch", "pull", "push":
                try Commands.networkUnavailable(command)
            default:
                Terminal.error("'\(command)' is not an sgit command. See 'sgit --help'.")
                return 1
            }
        } catch let error as GKError {
            Terminal.error(error.description)
            return 1
        } catch let error as SGitError {
            Terminal.error(error.description)
            return 1
        } catch {
            Terminal.error("\(error)")
            return 1
        }

        return 0
    }

    // MARK: - Help

    static func printHelp() {
        let title = Terminal.style("sgit", .bold, .cyan)
        Terminal.print("""
        \(title) — a command-line Git client powered by GitKit (v\(version))

        \(Terminal.style("USAGE", .bold))
            sgit <command> [options]

        \(Terminal.style("COMMANDS", .bold))
          \(Terminal.style("Start a working area", .dim))
            init [--bare] [path]        Create an empty Git repository
            clone <url> [path]          Clone a repository (network — unavailable)

          \(Terminal.style("Work on changes", .dim))
            status                      Show the working tree status
            add <path>... | .           Stage file contents for the next commit
            rm <path>...                Unstage files from the index
            commit -m <message>         Record staged changes to the repository
            reset [--soft|--mixed|--hard] [commit]
                                        Reset current HEAD to a given state
            stash [message]             Stash away changes in the working directory

          \(Terminal.style("Examine history & state", .dim))
            log [-n <count>]            Show commit logs
            diff [--staged]             Show changes between commits or the index
            tag [-a -m <msg>] [name]    List, create, or delete tags
                tag -d <name>

          \(Terminal.style("Branching & merging", .dim))
            branch [name]               List or create branches
                branch -d <name>        Delete a branch
                branch -m <old> <new>   Rename a branch
            checkout <branch|commit>    Switch branches or restore a commit
            merge <branch>              Join two development histories together

          \(Terminal.style("Collaborate", .dim))
            remote                      List remotes
                remote add <name> <url> Add a remote
                remote remove <name>    Remove a remote
            fetch / pull / push         Network sync (transport — unavailable)

          \(Terminal.style("Other", .dim))
            help, --help, -h            Show this help screen
            version, --version, -v      Show version information

        \(Terminal.style("EXAMPLES", .bold))
            sgit init
            sgit add .
            sgit commit -m "Initial commit"
            sgit log -n 5
            sgit branch feature
            sgit checkout feature

        \(Terminal.style("IDENTITY", .dim))
            Author identity is read from GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL,
            then user.name / user.email in the repository or ~/.gitconfig.
        """)
    }
}
