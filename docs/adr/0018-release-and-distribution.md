# ADR-0018: Releases as Notarized Zips on GitHub, Built from Tags

**Status:** Accepted
**Date:** 2026-10-29
**Deciders:** Christopher Bartling

## Context

`just bundle` signs the `.app` ad-hoc, so Gatekeeper rejects it on any Mac but the one that built it. The repo had no tags and no releases, and `Resources/Info.plist` was fixed at version `0.1.0`, build `1`. ADR-0006 left Developer ID signing, hardened runtime and notarization for "before any distribution outside this machine", and ADR-0009 left signing and notarization steps for "if distribution happens". This ADR settles both follow-ups. A Developer ID Application certificate (team `RDD45JXSRK`) exists.

## Decision

- **Releases are public GitHub Releases** on `cebartling/investment-simulator-2026`, downloaded and replaced by hand. There is no in-app update check.
- **A pushed tag starts a release.** `.github/workflows/release.yml` runs on `v*` tags. It fails, publishing nothing, unless the tag is `vMAJOR.MINOR.PATCH` and its commit is on `main`. Then it lints, tests, bundles, signs, notarizes, staples and runs `gh release create --generate-notes --verify-tag`. GitHub generates the release notes; there is no hand-written changelog.
- **The workflow only calls `just` recipes,** so a release can be rehearsed locally with the same steps:
  - `just bundle VERSION BUILD` stamps `CFBundleShortVersionString` and `CFBundleVersion` into the *bundled* `Info.plist` before signing, because editing it afterwards breaks the signature. Without arguments it leaves the plist alone.
  - `just bundle` signs with `CODESIGN_IDENTITY`, which defaults to `-` (ad-hoc). Any other identity adds hardened runtime (`--options runtime`) and a secure timestamp. Local builds and PR CI are unchanged.
  - `just release-zip VERSION` zips the `.app` with `ditto --keepParent` as `build/Investment-Simulator-VERSION.zip`.
  - `just notarize VERSION` submits the zip with `notarytool` and fails with the notary log unless the status is `Accepted`. It then staples the ticket to the `.app`, checks it with `stapler validate` and `spctl --assess`, and zips it again, because the uploaded zip has no ticket.
- **Versions come from the tag.** Tag `v1.2.3` gives version `1.2.3` and build number `GITHUB_RUN_NUMBER`. The committed `Info.plist` version is a placeholder for development builds and isn't bumped.
- **Hardened runtime with no entitlements.** The app makes outbound HTTPS requests and stores a generic-password Keychain item, and neither needs an entitlement outside the App Sandbox.
- **arm64 only.** `swift build -c release` on the Apple-silicon runner builds arm64. Intel Macs aren't supported.
- **Credentials live in the `release` GitHub Environment,** which only `v*` tags can deploy to, so no pull-request workflow can read them. The secrets are:
  - `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD`, imported into a temporary keychain that the run deletes
  - `NOTARY_API_KEY_P8_BASE64`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`, from an App Store Connect team API key with the Developer role

  Only the release job has `contents: write`; `ci.yml` stays `contents: read`.

## Options Considered

### Option A: Tag-driven GitHub Actions release of a notarized, stapled zip

**Pros:**
- Every release is built from a commit on `main`, in the same environment as CI.
- A zip of a stapled `.app` opens offline without a Gatekeeper warning, and needs nothing beyond `ditto`.
- Release notes and versions need no manual edits.

**Cons:**
- The signing certificate and notary key are stored as GitHub secrets.
- The tool installation is copied from `ci.yml`, so pins must be bumped in both workflows.

### Option B: Mac App Store

**Pros:**
- Automatic updates and Apple-hosted distribution.

**Cons:**
- Requires the App Sandbox, App Store review and provisioning profiles, none of which ADR-0006's SwiftPM-only build sets up.

### Option C: A DMG instead of a zip

**Pros:**
- The familiar drag-to-Applications window.

**Cons:**
- More tooling to build and sign a disk image, for one `.app`.

### Option D: Sparkle for updates

**Pros:**
- In-app update checks.

**Cons:**
- A third-party framework, an appcast to host, and a second signing key, for an app with few users.

### Option E: Versions bumped in the committed `Info.plist`

**Pros:**
- The repo shows the current version.

**Cons:**
- A commit per release, and the tag and plist can disagree.

## Consequences

- **Easier:** a release is `git tag vX.Y.Z && git push origin vX.Y.Z`. The download opens on any Apple-silicon Mac running macOS 26.
- **Harder:**
  - The signing identity's name is in `release.yml`. A renewed certificate means new secrets, and a new name there if the name changed.
  - A notarized app's signature differs from local builds, so the Keychain asks again before the released app can read the API key.
- **Revisit:**
  - A shared setup action, if a third workflow needs the same tools.
  - Universal binaries, if Intel support is ever needed.
  - The CI build artifact from ADR-0009, which this ADR doesn't add.
