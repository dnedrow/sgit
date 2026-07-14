# History Inspection Specification

## Purpose

Let users examine repository history and inspect changes between commits or
against the index.

## Requirements

### Requirement: Show commit history

The system SHALL print commit history when the user runs `log`, limiting the
number of commits shown, and SHALL default to a limit of 50 commits.

#### Scenario: Default history listing

- **WHEN** the user runs `sgit log`
- **THEN** up to 50 commits are printed, each showing the full commit hash, author, date, and message

#### Scenario: Limit the number of commits

- **WHEN** the user runs `sgit log -n <count>` (or `-<count>`)
- **THEN** at most `<count>` commits are printed

#### Scenario: Invalid count

- **WHEN** the user runs `sgit log -n <non-number>`
- **THEN** the system reports that `-n` requires a number
- **AND** exits with a non-zero status

#### Scenario: No commits yet

- **WHEN** the user runs `sgit log` in a repository with no commits
- **THEN** the system prints `No commits yet.`

#### Scenario: Merge commit display

- **WHEN** a commit in the log has more than one parent
- **THEN** the system prints a `Merge:` line listing the abbreviated parent hashes

### Requirement: Show changes with diff

The system SHALL show changes when the user runs `diff`, comparing the index to
HEAD when `--staged`/`--cached` is given, and otherwise comparing the two most
recent commits.

#### Scenario: Diff staged changes

- **WHEN** the user runs `sgit diff --staged` (or `--cached`)
- **THEN** the system prints the diff between the index and HEAD

#### Scenario: Diff recent commits

- **WHEN** the user runs `sgit diff` and at least two commits exist
- **THEN** the system prints the diff between the two most recent commits

#### Scenario: Not enough commits to diff

- **WHEN** the user runs `sgit diff` and fewer than two commits exist
- **THEN** the system advises that at least two commits are needed and suggests `sgit diff --staged`

#### Scenario: Diff output format

- **WHEN** a diff is printed
- **THEN** each delta shows a `diff --git` header, `---`/`+++` file lines, and hunks
- **AND** added lines, deleted lines, and context lines are distinguished
- **AND** a summary of files changed, insertions, and deletions is printed

#### Scenario: No changes

- **WHEN** a diff is computed and there are no deltas
- **THEN** the system prints `No changes.`
