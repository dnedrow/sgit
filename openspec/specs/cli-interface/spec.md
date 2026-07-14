# CLI Interface Specification

## Purpose

Provide a consistent command-line experience: dispatching subcommands, showing
help and version information, an optional activity spinner, colored terminal
output, and uniform error reporting with exit codes.

## Requirements

### Requirement: Dispatch subcommands

The system SHALL parse the first argument as a subcommand and dispatch to its
handler, showing help when no command is given and reporting unknown commands.

#### Scenario: No command given

- **WHEN** the user runs `sgit` with no arguments
- **THEN** the help screen is printed and the process exits successfully

#### Scenario: Unknown command

- **WHEN** the user runs `sgit <unknown>`
- **THEN** the system prints `'<unknown>' is not an sgit command. See 'sgit --help'.`
- **AND** exits with a non-zero status

### Requirement: Show help

The system SHALL print a help screen listing usage, global options, grouped
commands, and examples when the user runs `help`, `--help`, or `-h`.

#### Scenario: Request help

- **WHEN** the user runs `sgit help` (or `--help`, or `-h`)
- **THEN** the full help screen is printed

### Requirement: Show version

The system SHALL print the sgit version and the linked GitKit version when the
user runs `version`, `--version`, or `-v`, sourcing the sgit version from the
bundle's `CFBundleShortVersionString`.

#### Scenario: Request version

- **WHEN** the user runs `sgit version` (or `--version`, or `-v`)
- **THEN** the system prints `sgit version <version> (GitKit <gitkit-version>)`

### Requirement: Optional activity spinner

The system SHALL accept a global `--activity` flag placed anywhere in the
argument list, strip it before dispatch, and animate a spinner on standard error
while the command runs, only when standard error is an interactive terminal.

#### Scenario: Activity flag enables the spinner

- **WHEN** the user includes `--activity` and standard error is a TTY
- **THEN** a spinner with a command-appropriate label animates on standard error while the command runs

#### Scenario: Non-interactive output

- **WHEN** standard error is not an interactive terminal
- **THEN** no spinner is drawn, so piped or redirected output is not affected

#### Scenario: Spinner does not garble output

- **WHEN** the command emits output while the spinner is active
- **THEN** the spinner line is cleared before the output is written

### Requirement: Colored terminal output

The system SHALL emit ANSI color styling only when standard output is an
interactive terminal and the `NO_COLOR` environment variable is not set,
otherwise emitting plain text.

#### Scenario: Colors enabled on a TTY

- **WHEN** standard output is a TTY and `NO_COLOR` is unset
- **THEN** styled output includes ANSI color codes

#### Scenario: Colors disabled

- **WHEN** standard output is not a TTY or `NO_COLOR` is set
- **THEN** output is emitted as plain text without ANSI codes

### Requirement: Uniform error reporting

The system SHALL report errors from the command layer, GitKit, and other sources
to standard error with a red `error:` prefix, and SHALL exit with a non-zero
status on failure and zero on success.

#### Scenario: Command fails

- **WHEN** a command raises an error
- **THEN** the message is written to standard error prefixed with `error:`
- **AND** the process exits with a non-zero status

#### Scenario: Command succeeds

- **WHEN** a command completes without error
- **THEN** the process exits with a zero status
