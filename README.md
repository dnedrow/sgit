# sgit

A lightweight, native command-line Git client written in Swift and powered by [GitKit](https://github.com/dnedrow/GitKit). `sgit` implements core Git operations — from initializing repositories and staging changes to cloning, fetching, and pushing over HTTPS, SSH, and local transports.

> [!NOTE]
> sgit is not pure Swift. It links against the system **zlib** library (via `-lz`
> and a small Objective-C/C bridging header) to inflate and deflate Git
> packfile and object streams. A C toolchain with `zlib.h` available — standard
> on macOS — is therefore required to build.

> [!WARNING]
> **Work in progress — not production ready.** sgit is under active development and is
> **experimental**. APIs may change without notice, and the implementation has not been
> hardened against real-world edge cases. **No guarantees are made** regarding correctness,
> stability, or data integrity — using sgit against a repository you care about may lead
> to **data loss or corruption**. Always operate on backups or throwaway copies, and do not
> rely on it for critical or irreplaceable data. Use at your own risk.

## Building

sgit uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate its Xcode
project from the `project.yml` specification, so the `.xcodeproj` is not checked
in as the source of truth and must be regenerated whenever the project structure
changes.

Install XcodeGen (for example, via [Homebrew](https://brew.sh)):

```bash
brew install xcodegen
```

Then generate the Xcode project from the repository root:

```bash
xcodegen generate
```

Once generated, open `sgit.xcodeproj` in Xcode or build from the command line:

```bash
xcodebuild -project sgit.xcodeproj -scheme sgit build
```

> [!NOTE]
> The build links the system **zlib** (`-lz`) through the bridging header at
> `Sources/Bridging/sgit-Bridging-Header.h`, so it is not a pure-Swift build.
> The required `zlib.h` ships with the macOS SDK, so no extra packages are
> normally needed.

## Features

- **Repository management** — `init`, `clone`, `status`
- **Staging & committing** — `add`, `rm`, `commit`
- **History & inspection** — `log`, `diff`, `tag`
- **Branching & merging** — `branch`, `checkout`/`switch`, `merge`, `reset`, `stash`
- **Networking** — `remote`, `fetch`, `pull`, `push` (HTTPS, SSH, and local paths)

## Global Options

| Option       | Description                                                |
|--------------|------------------------------------------------------------|
| `--activity` | Show an animated activity spinner while the command runs   |

The `--activity` flag is optional and can be placed anywhere in the argument
list. The spinner is drawn on standard error and is shown only when running in
an interactive terminal, so it never interferes with piped or redirected output.

```bash
sgit --activity clone https://github.com/owner/repo.git
sgit --activity fetch origin
sgit --activity log -n 20
```

## Getting Help

Run `sgit` with no arguments, or use any of the help flags:

```
sgit help
sgit --help
sgit -h
```

This displays the full list of available commands, options, and usage examples.

To check the version:

```
sgit --version
```

## Quick Start

```bash
# Initialize a new repository
sgit init

# Stage all files and commit
sgit add .
sgit commit -m "Initial commit"

# View recent history
sgit log -n 5

# Create and switch to a new branch
sgit branch feature
sgit checkout feature

# Clone a remote repository
sgit clone https://github.com/owner/repo.git
sgit clone git@github.com:owner/repo.git
```

## Authentication

| Transport | Auth method                                                                             |
|-----------|-----------------------------------------------------------------------------------------|
| HTTPS     | URL userinfo, or `GIT_USERNAME` / `GIT_PASSWORD` (or `GIT_TOKEN`) environment variables |
| SSH       | `ssh://` or scp-style (`user@host:path`) — uses your SSH agent/keys                     |
| Local     | Filesystem paths or `file://` URLs                                                      |

## Author Identity

Author information is resolved in order:

1. `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` environment variables
2. `user.name` / `user.email` in the repository's `.git/config`
3. `user.name` / `user.email` in `~/.gitconfig`

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
