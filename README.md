# sgit

A lightweight, native command-line Git client written in Swift and powered by [GitKit](https://github.com/nickthedude/GitKit). `sgit` implements core Git operations — from initializing repositories and staging changes to cloning, fetching, and pushing over HTTPS, SSH, and local transports.

## Features

- **Repository management** — `init`, `clone`, `status`
- **Staging & committing** — `add`, `rm`, `commit`
- **History & inspection** — `log`, `diff`, `tag`
- **Branching & merging** — `branch`, `checkout`/`switch`, `merge`, `reset`, `stash`
- **Networking** — `remote`, `fetch`, `pull`, `push` (HTTPS, SSH, and local paths)

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
