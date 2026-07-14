## Why

`sgit` ships no prebuilt binaries: users must install XcodeGen, regenerate the
Xcode project, and build from source. Because `sgit` is distributed outside the
App Store, an unsigned/unnotarized binary would be quarantined by Gatekeeper on
download. We want each GitHub release to automatically carry a signed, notarized,
universal macOS binary that users can download and run without build tooling.

## What Changes

- Add a GitHub Actions workflow that triggers on `release: [published]`.
- Build a **universal** (`arm64` + `x86_64`) release binary via
  `xcodegen generate` + `xcodebuild`.
- Sign the binary with a **Developer ID Application** certificate using the
  **hardened runtime** (`codesign --options runtime --timestamp`).
- Package the binary plus the `share/man/man1/sgit.1` man page into a
  `.tar.gz` release asset.
- **Notarize the `.tar.gz`** with `notarytool` (App Store Connect API key).
  Do **not** staple — Gatekeeper verifies online on first run (stapling a bare
  Mach-O CLI is not supported).
- Upload the notarized archive to the triggering release as an asset.
- `project.yml` is intentionally **not** modified: signing is a post-build step,
  keeping local developer builds unchanged.

## Capabilities

### New Capabilities
- `release-automation`: Automated, signed, notarized universal-binary release
  artifacts produced and attached whenever a GitHub release is published.

### Modified Capabilities
<!-- None. No existing spec-level behavior changes. -->

## Impact

- **New file**: `.github/workflows/release.yml`.
- **New repo secrets**: Developer ID cert (.p12) + password, ephemeral keychain
  password, and App Store Connect API key (Key ID, Issuer ID, .p8).
- **Unchanged**: `project.yml`, `Sources/`, and local build flow.
- **External dependencies**: Apple Developer account, Homebrew `xcodegen` on the
  runner, Apple notarization service availability.
