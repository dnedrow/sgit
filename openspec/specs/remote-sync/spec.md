# Remote Synchronization Specification

## Purpose

Exchange objects and references with remote repositories over HTTPS, SSH, and
local transports: cloning, managing remotes, and running fetch, pull, and push.

## Requirements

### Requirement: Select a transport for a remote URL

The system SHALL classify a remote URL into an HTTP(S), SSH, or local transport
target, recognizing `http(s)://`, `ssh://`, scp-like `[user@]host:path`,
`file://`, and filesystem path forms.

#### Scenario: HTTP(S) URL

- **WHEN** a URL begins with `http://` or `https://`
- **THEN** it is classified as an HTTP transport target

#### Scenario: Explicit SSH URL

- **WHEN** a URL begins with `ssh://`
- **THEN** it is classified as an SSH target with its user, host, port, and path

#### Scenario: scp-like SSH URL

- **WHEN** a URL is of the form `[user@]host:path` with a colon before any slash
- **THEN** it is classified as an SSH target

#### Scenario: Local path or file URL

- **WHEN** a value is a `file://` URL or a filesystem path (absolute, relative, or `~`)
- **THEN** it is classified as a local transport target with an expanded, standardized path

### Requirement: Clone a repository

The system SHALL clone a repository from a URL into a destination directory when
the user runs `clone`, defaulting the directory name from the URL, refusing a
non-empty destination, materializing received objects, mirroring refs, setting up
`origin`, and checking out the default branch.

#### Scenario: Clone into a default directory

- **WHEN** the user runs `sgit clone <url>` with no directory
- **THEN** the repository is cloned into a directory derived from the URL (stripping any `.git` suffix)

#### Scenario: Clone into an explicit directory

- **WHEN** the user runs `sgit clone <url> <path>`
- **THEN** the repository is cloned into `<path>`

#### Scenario: Destination already populated

- **WHEN** the destination directory exists and is not empty
- **THEN** the system reports the destination already exists and is not empty
- **AND** exits with a non-zero status

#### Scenario: Empty remote

- **WHEN** the remote advertises no references
- **THEN** the system reports the remote has no references

#### Scenario: Successful clone setup

- **WHEN** a clone completes
- **THEN** received objects are written, remote refs and `origin/*` tracking refs are created, the `origin` remote URL is recorded, and the default branch is checked out

### Requirement: Manage remotes

The system SHALL list configured remotes when `remote` is run with no arguments,
and SHALL add or remove remotes via the `add` and `remove`/`rm` subcommands.

#### Scenario: List remotes

- **WHEN** the user runs `sgit remote`
- **THEN** configured remotes are listed alphabetically as `<name>\t<url>`

#### Scenario: Add a remote

- **WHEN** the user runs `sgit remote add <name> <url>`
- **THEN** the remote is added and the system prints `Added remote <name>.`

#### Scenario: Remove a remote

- **WHEN** the user runs `sgit remote remove <name>` (or `rm`)
- **THEN** the remote is removed and the system prints `Removed remote <name>.`

#### Scenario: Unknown remote subcommand

- **WHEN** the user runs `sgit remote <unknown>`
- **THEN** the system reports an unknown remote subcommand
- **AND** exits with a non-zero status

### Requirement: Resolve a remote argument

The system SHALL treat a remote argument that looks like a URL as a literal URL,
otherwise resolve it as a configured remote name, defaulting to `origin`, and
SHALL fail when no URL can be resolved.

#### Scenario: Literal URL argument

- **WHEN** a fetch/pull/push argument looks like a URL
- **THEN** it is used directly with the remote name `origin`

#### Scenario: Named remote

- **WHEN** the argument is a configured remote name (or omitted, defaulting to `origin`)
- **THEN** the remote's stored URL is used

#### Scenario: Unresolvable remote

- **WHEN** a named remote has no configured URL
- **THEN** the system reports that no URL is configured for the remote
- **AND** exits with a non-zero status

### Requirement: Fetch from a remote

The system SHALL download objects and update remote-tracking references when the
user runs `fetch`, requesting only advertised tips not already present locally.

#### Scenario: Fetch new objects

- **WHEN** the user runs `sgit fetch [remote|url]` and the remote has new objects
- **THEN** the new objects are received and remote-tracking refs are updated

#### Scenario: Already up to date

- **WHEN** the remote advertises nothing the local repository lacks
- **THEN** the system prints `Already up to date.`

### Requirement: Pull from a remote

The system SHALL fetch and then fast-forward the current branch when the user
runs `pull`, updating the working tree, and SHALL refuse to pull with a detached
HEAD.

#### Scenario: Fast-forward pull

- **WHEN** the user runs `sgit pull [remote|url]` and the remote branch is ahead
- **THEN** the current branch is fast-forwarded and the working tree is updated

#### Scenario: Up to date pull

- **WHEN** the local branch already matches the remote branch
- **THEN** the system prints `Already up to date.`

#### Scenario: Detached HEAD

- **WHEN** the user runs `sgit pull` while HEAD is detached
- **THEN** the system reports it cannot pull with a detached HEAD
- **AND** exits with a non-zero status

### Requirement: Push to a remote

The system SHALL upload the specified branch to a remote when the user runs
`push`, defaulting the branch to the current branch (or `main`).

#### Scenario: Push the current branch

- **WHEN** the user runs `sgit push [remote|url]` with no branch
- **THEN** the current branch is pushed and the system prints `Pushed <branch> to <remote>.`

#### Scenario: Push an explicit branch

- **WHEN** the user runs `sgit push [remote|url] <branch>`
- **THEN** `<branch>` is pushed to the remote

### Requirement: Authenticate to remotes

The system SHALL authenticate to HTTPS remotes using URL userinfo or the
`GIT_USERNAME`/`GIT_PASSWORD` (or `GIT_TOKEN`) environment variables, and SHALL
authenticate to SSH remotes using the user's SSH agent and keys.

#### Scenario: HTTPS credentials from environment

- **WHEN** an HTTPS operation runs without userinfo in the URL
- **THEN** credentials are taken from `GIT_USERNAME`/`GIT_PASSWORD` or `GIT_TOKEN`

#### Scenario: SSH key authentication

- **WHEN** an SSH operation runs
- **THEN** authentication uses the user's SSH agent/keys
