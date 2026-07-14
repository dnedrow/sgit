## Context

`sgit` is a macOS command-line tool built with XcodeGen + `xcodebuild`. The
`.xcodeproj` is generated, not checked in, so any build (local or CI) must run
`xcodegen generate` first. There are currently no release binaries; users build
from source. Because distribution is outside the App Store, a downloaded binary
must be Developer ID signed and notarized or Gatekeeper will quarantine it.

The author has an Apple Developer account with a Developer ID Application
certificate. GitHub-hosted macOS runners provide Xcode, `codesign`, `lipo`, and
`xcrun notarytool`.

## Goals / Non-Goals

**Goals:**
- Automatically produce a universal (`arm64` + `x86_64`), Developer ID signed,
  hardened-runtime, notarized `sgit` binary on every published release.
- Package the binary with its man page as a `.tar.gz` and attach it to the
  release.
- Keep `project.yml` and the local build flow unchanged.

**Non-Goals:**
- Stapling (unsupported for a bare Mach-O CLI; online verification is accepted).
- Homebrew tap / formula automation.
- App Store distribution or `.pkg`/`.dmg` installers.
- Multi-OS or Linux builds.

## Decisions

**Sign as a post-build step, not in Xcode.**
Run `xcodebuild ... CODE_SIGNING_ALLOWED=NO` to produce an unsigned universal
binary, then `codesign` it directly. *Alternative:* configure manual signing in
`project.yml`. *Rejected* because it forces signing config on every local build
and adds Xcode signing-phase complexity in a headless runner.

**Universal binary via `ARCHS`.**
Build with `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`. *Alternative:* build two
binaries and `lipo -create`. *Rejected* as unnecessary — a single xcodebuild
invocation yields the fat binary directly.

**Hardened runtime, no entitlements.**
Sign with `--options runtime --timestamp`. The tool only links system zlib and
needs no special entitlements, so no entitlements plist is required. Hardened
runtime is mandatory for notarization.

**Notarize the tarball, skip stapling.**
Submit the `.tar.gz` with `notarytool submit --wait`. Stapling a raw executable
is not supported; Gatekeeper performs an online check on first run. *Alternative:*
wrap in `.pkg`/`.dmg` to enable offline stapling. *Rejected* as overkill for a
`curl`/`brew`-style CLI.

**App Store Connect API key for notarization.**
Use `--key-id / --issuer / --key` (.p8) rather than Apple-ID + app-specific
password. Modern, less brittle, no 2FA friction.

**Ephemeral keychain.**
Import the .p12 into a temporary keychain created and deleted within the job so
no signing material persists on the runner.

## Risks / Trade-offs

- Secret misconfiguration breaks releases → fail fast with clear steps; document
  required secrets; guard `codesign --verify` before upload.
- No stapling means first-run needs network for Gatekeeper → acceptable and
  documented; matches common CLI distribution.
- GitHub runner Xcode/`notarytool` version drift → pin `macos-latest` behavior
  and surface `notarytool` log on failure.
- Certificate expiry → surface `codesign` errors clearly; out of workflow scope.
- Universal build increases artifact size → acceptable for portability.

## Migration Plan

1. Add repo secrets (Developer ID .p12 + password, keychain password, App Store
   Connect API key: Key ID, Issuer ID, .p8 base64).
2. Add `.github/workflows/release.yml`.
3. Publish a test/pre-release tag to validate end-to-end.
4. Rollback: delete/disable the workflow; releases simply carry no binary asset.

## Open Questions

- None blocking. Optionally add SHA-256 checksum asset and/or `--version`
  smoke test in a future change.
