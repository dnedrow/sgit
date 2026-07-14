# Release Automation Specification

## Purpose

Automatically produce a signed, notarized, universal macOS `sgit` binary and
attach it as a downloadable asset whenever a GitHub release is published, so
users can run `sgit` without build tooling and without Gatekeeper quarantine.

## Requirements

### Requirement: Release-triggered build

The workflow SHALL run automatically when a GitHub release is published, and
SHALL build against the exact source of the release's tag.

#### Scenario: Release published

- **WHEN** a GitHub release is published for tag `vX.Y.Z`
- **THEN** the workflow checks out that tag, runs `xcodegen generate`, and builds
  the `sgit` scheme in the `Release` configuration

#### Scenario: Non-release events do not trigger

- **WHEN** a commit is pushed or a pull request is opened
- **THEN** the release workflow does not run

### Requirement: Universal binary

The workflow SHALL produce a single macOS binary containing both `arm64` and
`x86_64` architectures.

#### Scenario: Architectures present

- **WHEN** the build completes
- **THEN** `lipo -archs` on the produced `sgit` binary reports both `arm64` and
  `x86_64`

### Requirement: Developer ID signing with hardened runtime

The workflow SHALL sign the binary with a Developer ID Application certificate
using the hardened runtime and a secure timestamp, and SHALL fail if signing
does not succeed.

#### Scenario: Successful signing

- **WHEN** the binary is signed
- **THEN** `codesign --verify --strict` succeeds and `codesign -d --verbose`
  reports the Developer ID Application authority and the `runtime` flag

#### Scenario: Missing signing credentials

- **WHEN** the Developer ID certificate secrets are absent or invalid
- **THEN** the workflow fails and no asset is uploaded

### Requirement: Packaging with man page

The workflow SHALL package the signed binary together with the
`share/man/man1/sgit.1` man page into a gzip-compressed tar archive named for
the release tag.

#### Scenario: Archive contents

- **WHEN** the archive is produced for tag `vX.Y.Z`
- **THEN** the file is named `sgit-vX.Y.Z-universal-macos.tar.gz` and contains
  both the `sgit` executable and `sgit.1`

### Requirement: Notarization of the archive

The workflow SHALL submit the `.tar.gz` to Apple's notary service via
`notarytool` and wait for acceptance. The workflow SHALL NOT staple the ticket.

#### Scenario: Notarization accepted

- **WHEN** the archive is submitted to `notarytool submit --wait`
- **THEN** the service returns status `Accepted` and the workflow proceeds

#### Scenario: Notarization rejected

- **WHEN** `notarytool` returns a status other than `Accepted`
- **THEN** the workflow fails and no asset is uploaded

### Requirement: Release asset upload

The workflow SHALL upload the notarized archive as an asset on the triggering
release.

#### Scenario: Asset attached

- **WHEN** notarization succeeds
- **THEN** the `sgit-vX.Y.Z-universal-macos.tar.gz` asset appears on the
  release `vX.Y.Z`

### Requirement: Local build flow unchanged

The change SHALL NOT modify `project.yml` or the documented local build flow.

#### Scenario: project.yml untouched

- **WHEN** the change is applied
- **THEN** `project.yml` is unchanged and `xcodegen generate` + `xcodebuild`
  still build locally without signing configuration
