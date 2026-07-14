# Committing Specification

## Purpose

Record staged changes into the repository as commits, attributing each commit to
an author identity resolved from the environment and Git configuration.

## Requirements

### Requirement: Create a commit from staged changes

The system SHALL create a commit from the current index when the user runs
`commit` with a message via `-m`/`--message`, and SHALL reject the command when
no non-empty message is supplied.

#### Scenario: Commit with a message

- **WHEN** the user runs `sgit commit -m "<message>"`
- **THEN** a commit recording the staged changes is created with that message
- **AND** the system prints `[<branch> <short-oid>] <first message line>`

#### Scenario: Missing commit message

- **WHEN** the user runs `sgit commit` without a non-empty `-m` message
- **THEN** the system reports that a commit message is required
- **AND** exits with a non-zero status

### Requirement: Resolve author identity

The system SHALL resolve the commit author name and email in priority order:
environment variables, then repository config, then global `~/.gitconfig`, and
SHALL fall back to the current system user when none are configured.

#### Scenario: Identity from environment variables

- **WHEN** `GIT_AUTHOR_NAME` and/or `GIT_AUTHOR_EMAIL` are set
- **THEN** those values are used for the commit author, taking precedence over configuration

#### Scenario: Identity from Git configuration

- **WHEN** the author environment variables are not set
- **THEN** `user.name` and `user.email` are read from the repository config, falling back to `~/.gitconfig`

#### Scenario: Identity fallback

- **WHEN** no author identity is configured in the environment or Git config
- **THEN** the system uses the current system user name and a `<user>@<host>` email

#### Scenario: Commit timestamp

- **WHEN** a commit is created
- **THEN** the author time is the current date with the local time-zone offset
