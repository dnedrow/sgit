# Repository Management Specification

## Purpose

Create local Git repositories and locate the repository that contains the
current working directory, so that all other commands operate on a well-defined
repository. Also report the state of the working tree relative to the index and
HEAD.

## Requirements

### Requirement: Initialize a repository

The system SHALL create an empty Git repository when the user runs `init`,
defaulting to the current working directory when no path is given, and
creating a bare repository when `--bare` is supplied.

#### Scenario: Initialize in the current directory

- **WHEN** the user runs `sgit init` with no path argument
- **THEN** an empty Git repository is created rooted at the current working directory
- **AND** the system prints `Initialized empty Git repository in <git-dir>`

#### Scenario: Initialize at an explicit path

- **WHEN** the user runs `sgit init <path>`
- **THEN** an empty Git repository is created at `<path>`

#### Scenario: Initialize a bare repository

- **WHEN** the user runs `sgit init --bare`
- **THEN** a bare repository is created
- **AND** the system prints `Initialized empty Git bare repository in <git-dir>`

### Requirement: Discover the enclosing repository

The system SHALL locate the repository by walking up from the current working
directory until it finds a directory containing a `.git` folder, resolving
symlinks to a canonical physical path, and SHALL fail with a clear error when no
repository is found.

#### Scenario: Command run inside a repository subdirectory

- **WHEN** the user runs a repository command from a subdirectory of a repository
- **THEN** the system discovers the enclosing repository by ascending to the directory containing `.git`

#### Scenario: Command run outside any repository

- **WHEN** the user runs a repository command outside of any Git repository
- **THEN** the system reports `not a git repository (or any of the parent directories): .git`
- **AND** exits with a non-zero status

### Requirement: Report working tree status

The system SHALL report the current branch or detached HEAD, and list staged,
unstaged, and untracked changes when the user runs `status` (aliased as `st`).

#### Scenario: Clean working tree

- **WHEN** the user runs `sgit status` and there are no changes
- **THEN** the system prints the current branch
- **AND** prints `nothing to commit, working tree clean`

#### Scenario: Pending changes present

- **WHEN** the user runs `sgit status` with staged, unstaged, or untracked changes
- **THEN** staged changes are listed under "Changes to be committed"
- **AND** unstaged changes are listed under "Changes not staged for commit"
- **AND** untracked files are listed under "Untracked files"
- **AND** each path is sorted and labeled with its change type

#### Scenario: Detached HEAD

- **WHEN** the user runs `sgit status` while HEAD is detached
- **THEN** the system prints `HEAD detached at <short-oid>`
