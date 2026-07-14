# Branching and Refs Specification

## Purpose

Manage branches, tags, and the working tree's position within history:
creating, listing, renaming, and deleting refs; switching between branches and
commits; merging histories; resetting HEAD; and stashing work in progress.

## Requirements

### Requirement: Manage branches

The system SHALL list branches when `branch` is run with no arguments, and SHALL
create, delete (`-d`/`--delete`), or rename (`-m`/`--move`) branches based on the
supplied arguments.

#### Scenario: List branches

- **WHEN** the user runs `sgit branch` with no arguments
- **THEN** branches are listed alphabetically with the current branch marked by `*`

#### Scenario: No branches yet

- **WHEN** the user runs `sgit branch` and no branches exist
- **THEN** the system prints `No branches yet.`

#### Scenario: Create a branch

- **WHEN** the user runs `sgit branch <name>`
- **THEN** a branch `<name>` is created and the system prints `Created branch <name>.`

#### Scenario: Delete a branch

- **WHEN** the user runs `sgit branch -d <name>`
- **THEN** branch `<name>` is deleted and the system prints `Deleted branch <name>.`

#### Scenario: Rename a branch

- **WHEN** the user runs `sgit branch -m <old> <new>`
- **THEN** branch `<old>` is renamed to `<new>` and the system prints `Renamed branch <old> to <new>.`

### Requirement: Switch branches or commits

The system SHALL switch to a branch or check out a commit when the user runs
`checkout` (aliased as `switch`), preferring a matching branch name and falling
back to a full commit hash, entering detached HEAD for a commit.

#### Scenario: Checkout a branch

- **WHEN** the user runs `sgit checkout <branch>` and `<branch>` exists
- **THEN** the working tree switches to that branch and the system prints `Switched to branch '<branch>'`

#### Scenario: Checkout a commit

- **WHEN** the user runs `sgit checkout <full-commit-hash>` that is not a branch name
- **THEN** the working tree switches to that commit in detached HEAD state

#### Scenario: Unknown target

- **WHEN** the user runs `sgit checkout <target>` that is neither a known branch nor a valid commit hash
- **THEN** the system reports that the target is not a known branch or full commit hash
- **AND** exits with a non-zero status

### Requirement: Merge a branch

The system SHALL merge a named branch into the current branch when the user runs
`merge`, attributing any merge commit to the resolved author identity.

#### Scenario: Merge a branch

- **WHEN** the user runs `sgit merge <branch>`
- **THEN** the branch is merged and the system prints the resulting short OID

#### Scenario: Missing merge target

- **WHEN** the user runs `sgit merge` with no branch
- **THEN** the system reports that a branch to merge is required
- **AND** exits with a non-zero status

### Requirement: Reset HEAD

The system SHALL reset HEAD to a target commit when the user runs `reset`,
supporting `--soft`, `--mixed` (default), and `--hard` modes, and defaulting to
the current HEAD commit when no target is given.

#### Scenario: Reset with a mode

- **WHEN** the user runs `sgit reset [--soft|--mixed|--hard] [commit]`
- **THEN** HEAD is reset using the chosen mode and the system prints `HEAD is now at <short-oid>`

#### Scenario: Default target

- **WHEN** the user runs `sgit reset` with no commit
- **THEN** HEAD is reset to the current HEAD commit

#### Scenario: Invalid target

- **WHEN** the user provides a reset target that is not a full 40-character commit hash
- **THEN** the system reports the target must be a full commit hash
- **AND** exits with a non-zero status

### Requirement: Stash working changes

The system SHALL save the current working directory state when the user runs
`stash`, accepting an optional message.

#### Scenario: Stash changes

- **WHEN** the user runs `sgit stash [message]`
- **THEN** the working directory state is saved and the system prints the saved state's short OID

### Requirement: Manage tags

The system SHALL list tags when `tag` is run with no arguments, and SHALL create
lightweight tags, annotated tags (`-a` with `-m`), or delete tags (`-d`) based on
the supplied arguments.

#### Scenario: List tags

- **WHEN** the user runs `sgit tag` with no arguments
- **THEN** tags are listed alphabetically by short name

#### Scenario: Create a lightweight tag

- **WHEN** the user runs `sgit tag <name>`
- **THEN** a lightweight tag `<name>` is created and the system prints `Created tag <name>.`

#### Scenario: Create an annotated tag

- **WHEN** the user runs `sgit tag -a <name> -m <message>`
- **THEN** an annotated tag `<name>` is created with the resolved tagger identity and message

#### Scenario: Delete a tag

- **WHEN** the user runs `sgit tag -d <name>`
- **THEN** tag `<name>` is deleted and the system prints `Deleted tag <name>.`
