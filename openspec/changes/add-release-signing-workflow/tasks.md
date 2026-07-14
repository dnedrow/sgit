## 1. Prerequisites (repo configuration)

- [x] 1.1 Export the Developer ID Application cert + private key as a `.p12`; base64-encode and add secret `DEVELOPER_ID_CERT_P12`
- [x] 1.2 Add secret `DEVELOPER_ID_CERT_PASSWORD` (the .p12 password)
- [x] 1.3 Add secret `KEYCHAIN_PASSWORD` (random string for the ephemeral keychain)
- [x] 1.4 Create an App Store Connect API key; add secrets `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, and `AC_API_KEY_P8` (base64 of the .p8)
- [x] 1.5 Note the signing identity name (e.g. `Developer ID Application: Name (TEAMID)`) for the `codesign` step

## 2. Workflow scaffold

- [x] 2.1 Create `.github/workflows/release.yml` with `on: release: types: [published]` and a `macos-latest` job
- [x] 2.2 Add `permissions: contents: write` (needed to upload release assets)
- [x] 2.3 Check out the repo at the release tag and export `TAG=${{ github.event.release.tag_name }}`
- [x] 2.4 Install XcodeGen (`brew install xcodegen`) and run `xcodegen generate`

## 3. Build

- [x] 3.1 Run `xcodebuild -project sgit.xcodeproj -scheme sgit -configuration Release -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build`
- [x] 3.2 Locate the built `sgit` binary and verify it is universal with `lipo -archs`

## 4. Sign

- [x] 4.1 Create a temporary keychain using `KEYCHAIN_PASSWORD`; set it default and unlock it
- [x] 4.2 Import `DEVELOPER_ID_CERT_P12` into the keychain and set key partition list for `codesign`
- [x] 4.3 Sign: `codesign --force --options runtime --timestamp --sign "<identity>" sgit`
- [x] 4.4 Verify with `codesign --verify --strict --verbose=2 sgit` and `codesign -d --verbose=4 sgit`

## 5. Package

- [x] 5.1 Stage the signed `sgit` binary and `share/man/man1/sgit.1` into a clean directory
- [x] 5.2 Create `sgit-${TAG}-universal-macos.tar.gz` containing `sgit` and `sgit.1`

## 6. Notarize

- [x] 6.1 Write the `.p8` from `AC_API_KEY_P8` to a temp file
- [x] 6.2 Submit: `xcrun notarytool submit sgit-${TAG}-universal-macos.tar.gz --key <p8> --key-id $AC_API_KEY_ID --issuer $AC_API_ISSUER_ID --wait`
- [x] 6.3 Fail the job if the returned status is not `Accepted` (print the notary log on failure)

## 7. Upload & cleanup

- [x] 7.1 Upload the archive to the release with `gh release upload "$TAG" sgit-${TAG}-universal-macos.tar.gz`
- [x] 7.2 Delete the temporary keychain and remove the `.p8`/`.p12` temp files (run in an `always()` cleanup step)

## 8. Validation & docs

- [ ] 8.1 Publish a pre-release tag and confirm the asset attaches and `codesign`/notarization succeed
- [ ] 8.2 On a clean Mac, download, extract, and run `sgit --version` to confirm Gatekeeper accepts it
- [x] 8.3 Update `README.md` with a "Download" section pointing users to release assets
