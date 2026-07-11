# Publishing Checklist

This app can be distributed as a local ad-hoc build for personal use, or as a Developer ID signed and notarized macOS app for public distribution.

## Local Release

Run a full local verification before sharing any artifact:

```bash
make verify-release
```

This runs Swift complete concurrency checking with warnings treated as errors, builds the universal app, runs tests, validates plists and privacy manifests, verifies the app signature, creates the zip and DMG, writes SHA-256 checksum files, verifies the DMG, and verifies the release manifest, including the actual executable architectures and code-signature metadata.

In a logged-in macOS desktop session, verify the transient menu-bar popover behavior separately:

```bash
make verify-runtime
```

This launches an isolated instance of the exact built bundle, confirms its popover appears, activates Finder, requires the popover to disappear, terminates the isolated instance, and restores the previously focused app.

For a public upload candidate, run the stricter gate after committing your source changes:

```bash
make verify-public-release BUNDLE_IDENTIFIER="com.yourdomain.codexusagemonitor"
```

This includes `verify-release`, then fails unless the working tree is clean, `BUNDLE_IDENTIFIER` is a non-placeholder reverse-DNS identifier, the manifest matches the current commit, and the manifest records `"gitDirty": false`.

Local artifacts are written to the configured `OUT_DIR`:

```text
CodexUsageMonitor.app
CodexUsageMonitor-0.4.1.zip
CodexUsageMonitor-0.4.1.zip.sha256
CodexUsageMonitor-0.4.1.dmg
CodexUsageMonitor-0.4.1.dmg.sha256
CodexUsageMonitor-0.4.1.manifest.json
```

## Public Source Repository

Do not push the development repository history directly to a public remote. Early commits contain a local absolute path, and the development commits use a machine-local author email. The current tracked snapshot is clean, but Git preserves removed content and original author metadata.

Validate the current snapshot:

```bash
make verify-public-source
```

Audit the full development history separately:

```bash
make audit-public-history
```

That history audit is expected to reject this development repository. The public MIT-licensed repository is [Heaaaaaaaa/Codex-Usage-Monitor](https://github.com/Heaaaaaaaa/Codex-Usage-Monitor), seeded without the development history. Generate a clean tracked snapshot for public updates with:

```bash
make source-archive
```

This creates `CodexUsageMonitor-0.4.1-source.zip` and its SHA-256 file from tracked `HEAD` only. Apply that snapshot to a clean clone of the public repository, preserve its existing `.git` directory and `LICENSE`, and commit with the configured GitHub no-reply identity. Run `make audit-public-history` in the public clone and require it to pass before every push. The source validator rejects tracked credentials, private keys, raw JSONL/log files, generated build directories, current-user absolute home paths, unsafe ZIP paths, and symbolic links.

## Public Release

Public distribution outside your own Mac needs:

- Apple Developer Program membership.
- A Developer ID Application certificate installed in Keychain.
- A stored `notarytool` keychain profile.
- A stable reverse-DNS bundle identifier.

Create the notary profile once:

```bash
xcrun notarytool store-credentials "CodexUsageMonitorNotary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Build a signed, notarized, stapled DMG:

```bash
make publish-preflight \
  BUNDLE_IDENTIFIER="com.yourdomain.codexusagemonitor" \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="CodexUsageMonitorNotary"

make release-dmg-notarized \
  BUNDLE_IDENTIFIER="com.yourdomain.codexusagemonitor" \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="CodexUsageMonitorNotary"
```

`make publish-preflight` checks local release prerequisites, app bundle metadata, universal binary slices, bundled privacy manifest, minimal release entitlements, `Developer ID Application: ... (TEAMID)` signing identity, and notary profile name without contacting Apple by default. Add `CHECK_NOTARY=1` when you want it to validate the stored notary profile with Apple's notary service. `make release-dmg-notarized` verifies the final manifest with the Developer ID signature policy, so an ad-hoc, Apple Development, or non-hardened runtime app signature cannot pass as a public distribution build.

Set `NOTARY_KEYCHAIN=/path/to/keychain-db` when the notary profile is stored in a file-based keychain, such as a temporary CI keychain.

## Automated GitHub Release

`.github/workflows/publish-release.yml` runs only for pushed `v*` tags. It validates that the tag, `Makefile`, `Info.plist`, changelog, and documented artifact names agree; imports the Developer ID certificate into a temporary keychain; notarizes and staples the app and DMG; verifies the Developer ID release manifest; uploads workflow artifacts; and creates the GitHub release. The temporary certificate and keychain are removed even when a step fails.

Create a GitHub environment named `release`, optionally add required reviewers, and configure these environment or repository secrets:

- `APPLE_DEVELOPER_ID_P12_BASE64`: Base64 representation of the exported Developer ID Application certificate and private key (`.p12`).
- `APPLE_DEVELOPER_ID_P12_PASSWORD`: Password used when exporting the `.p12`.
- `APPLE_SIGN_IDENTITY`: Exact Keychain identity, such as `Developer ID Application: Your Name (TEAMID)`.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password used by `notarytool`.

On macOS, prepare and upload the certificate secret without committing either file:

```bash
base64 -i DeveloperIDApplication.p12 -o DeveloperIDApplication.p12.base64
gh secret set --env release APPLE_DEVELOPER_ID_P12_BASE64 < DeveloperIDApplication.p12.base64
```

Set the remaining secrets through GitHub repository settings or `gh secret set --env release`. Base64 is an encoding rather than encryption; the value is protected by GitHub only after it is stored as an encrypted secret. See GitHub's [encrypted secrets guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) and Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Before pushing a release tag, validate it locally:

```bash
python3 Tools/ValidateReleaseVersion.py --repo . --tag v0.4.1
git tag -a v0.4.1 -m "Codex Usage Monitor 0.4.1"
git push origin v0.4.1
```

The workflow uses the repository-scoped `GITHUB_TOKEN` with only `contents: write` to create the release. It refuses to create a release for a missing remote tag.

## Final Checks

Before publishing:

- Confirm `make verify-runtime` passes in a logged-in macOS desktop session.
- Confirm `make verify-public-artifacts` passes in the artifact folder layout you plan to upload.
- Confirm the manifest lists `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.
- Confirm the manifest `pricing` section lists the shipped model rates, source URL, verified date, and estimate limitations.
- Confirm the manifest `signature` section matches the intended signing identity for the public build and reports hardened runtime.
- Confirm `UsageStore.defaultRates` and `defaultRateVerifiedDate` still match the public [OpenAI API pricing](https://developers.openai.com/api/docs/pricing) page.
- Verify checksum files with `shasum -a 256 -c`.
- Use the DMG as the primary public download.
- Keep the zip, checksum files, and manifest attached to the release for auditing.
- Confirm the app still reads only the selected local Codex log folder, writes only local preferences/cache data, and does not read auth files.
- Review `PRIVACY.md` against the release behavior and publish it alongside the download page.
- Confirm `SUPPORT.md`, `SECURITY.md`, and the privacy-preserving bug-report template are present in the public repository.
- Do not describe an ad-hoc artifact from `verify-public-release` as notarized; only the credentialed `release-dmg-notarized` output is a public Gatekeeper-ready build.
- Confirm the release tag passes `Tools/ValidateReleaseVersion.py` before pushing it.
- Confirm `make verify-public-source` passes for the release snapshot.
- Confirm the public repository was seeded from the clean source archive and `make audit-public-history` passes there.
- Confirm the chosen license and public commit identity are intentional before the first push.
