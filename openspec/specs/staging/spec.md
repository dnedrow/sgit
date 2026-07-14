# Staging Specification

## Purpose

Manage the contents of the Git index (staging area) by adding file contents to
be included in the next commit and removing entries from the index.

## Requirements

### Requirement: Stage specific paths

The system SHALL stage the file contents at each path passed to `add` so they
are included in the next commit, and SHALL reject the command when no path is
given.

#### Scenario: Stage one or more explicit paths

- **WHEN** the user runs `sgit add <path>...`
- **THEN** each named path is staged into the index

#### Scenario: No path provided

- **WHEN** the user runs `sgit add` with no arguments
- **THEN** the system reports that nothing was specified and nothing was added
- **AND** exits with a non-zero status

### Requirement: Stage all pending changes

The system SHALL stage every untracked and unstaged change when the user passes
`.`, `-A`, or `--all` to `add`, and SHALL report how many files were staged.

#### Scenario: Stage everything

- **WHEN** the user runs `sgit add .` (or `-A`, or `--all`)
- **THEN** all untracked and unstaged paths are staged
- **AND** the system prints `Staged <n> file(s).`

### Requirement: Unstage paths

The system SHALL remove each named path from the index when the user runs `rm`,
and SHALL reject the command when no path is given.

#### Scenario: Remove paths from the index

- **WHEN** the user runs `sgit rm <path>...`
- **THEN** each named path is removed from the index

#### Scenario: No path provided to rm

- **WHEN** the user runs `sgit rm` with no arguments
- **THEN** the system reports that no paths were given
- **AND** exits with a non-zero status
