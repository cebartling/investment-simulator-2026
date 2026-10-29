# Releasing

Releases are notarized `.app` zips published to [GitHub Releases](https://github.com/cebartling/investment-simulator-2026/releases), built by `.github/workflows/release.yml` when a `vMAJOR.MINOR.PATCH` tag is pushed. [ADR-0018](adr/0018-release-and-distribution.md) records the decision. This guide covers the one-time setup, a local rehearsal, and cutting a release.

## One-time setup

### 1. Create the `release` environment

The signing and notary secrets live in a GitHub Environment that only `v*` tags can deploy to, so no pull-request workflow can read them.

In the web UI:

1. Go to **Settings → Environments → New environment** and name it `release`.
2. Under **Deployment branches and tags**, choose **Selected branches and tags → Add deployment branch or tag rule**.
3. Set **Ref type** to **Tag** and the pattern to `v*`, then save.
4. Optionally, add yourself under **Required reviewers**. Each release then waits for an approval before any secret is read.

Or from a terminal:

```bash
gh api -X PUT repos/cebartling/investment-simulator-2026/environments/release \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/cebartling/investment-simulator-2026/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag
```

### 2. Export the Developer ID certificate as a `.p12`

1. Open **Keychain Access → login → My Certificates**.
2. Expand **Developer ID Application: Christopher Bartling (RDD45JXSRK)** and check that a private key is nested under it.
3. Right-click the certificate and choose **Export…**. Pick **Personal Information Exchange (.p12)** and save it outside the repo, e.g. `~/Desktop/developer-id.p12`.
4. Set a strong export password. It becomes `DEVELOPER_ID_P12_PASSWORD`.

The `.p12` doesn't need Apple's intermediate certificate, because the workflow downloads and imports both Developer ID intermediates, pinned by SHA-256.

### 3. Create the App Store Connect API key for notarization

1. In [App Store Connect](https://appstoreconnect.apple.com), go to **Users and Access → Integrations → App Store Connect API → Team Keys**.
2. Click **Generate API Key**, name it e.g. `investment-simulator-notary`, and choose the **Developer** role.
3. **Download the `.p8` right away.** Apple lets you download it only once. Keep it outside the repo, e.g. in `~/.private_keys/`.
4. Note two values:
   - the **Key ID** from the key's row, which becomes `NOTARY_KEY_ID`
   - the **Issuer ID**, the UUID shown above the table, which becomes `NOTARY_ISSUER_ID`

### 4. Store the secrets in the environment

Run these in your own terminal. Piping and prompting keep the values out of your shell history:

```bash
base64 -i ~/Desktop/developer-id.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env release
gh secret set DEVELOPER_ID_P12_PASSWORD --env release        # prompts for the export password
base64 -i ~/.private_keys/AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_API_KEY_P8_BASE64 --env release
gh secret set NOTARY_KEY_ID --env release                    # prompts for the Key ID
gh secret set NOTARY_ISSUER_ID --env release                 # prompts for the Issuer ID
gh secret list --env release                                 # lists all five
```

Store them as **environment** secrets, not repository secrets. Only the environment's tag rule keeps them away from pull-request workflows.

Then delete the exported `.p12`; the certificate stays in your keychain. Keep the `.p8`, because it can't be downloaded again.

## Rehearse locally

The workflow only calls `just` recipes, so a release can be rehearsed locally with the same steps:

```bash
export NOTARY_KEY_PATH=~/.private_keys/AuthKey_XXXXXXXXXX.p8 NOTARY_KEY_ID=… NOTARY_ISSUER_ID=…
CODESIGN_IDENTITY="Developer ID Application: Christopher Bartling (RDD45JXSRK)" just bundle 0.1.0 1
just release-zip 0.1.0
just notarize 0.1.0
```

`just notarize` ends with `spctl` reporting `source=Notarized Developer ID`. `codesign -dv --verbose=4 "build/Investment Simulator.app"` shows `flags=0x10000(runtime)` and a `Timestamp`.

The first signing asks for Keychain access to the private key. Answer the dialog promptly; see Troubleshooting.

Then launch the notarized app, enter the Equibles key in Settings, open an experiment and click Refresh Prices. This confirms hardened runtime doesn't block networking or the Keychain. Expect one Keychain prompt, because the signature differs from development builds.

## Cut a release

Tag a commit that is on `main` and push the tag:

```bash
git switch main && git pull
git tag v0.1.0
git push origin v0.1.0
```

- **Watch the run** under [Actions → Release](https://github.com/cebartling/investment-simulator-2026/actions/workflows/release.yml), or with `gh run watch`.
- **What the workflow does:** checks the tag and the secrets, lints, tests, signs, notarizes and staples.
- **The result:** a release on the [Releases page](https://github.com/cebartling/investment-simulator-2026/releases) with `Investment-Simulator-<version>.zip` and generated notes.
- **Version numbers:** the version comes from the tag and the build number from the workflow run number. The committed `Resources/Info.plist` version is a development placeholder; don't bump it.

To check a release:

1. Download the zip in a browser, so it gets the quarantine flag.
2. Unzip it and open the app. It should open without a Gatekeeper warning, even offline.
3. Check that **About** shows the tag's version.

## Troubleshooting

- **The run fails at "Check the tag".** The tag isn't `vMAJOR.MINOR.PATCH`, or its commit isn't on `main`. Delete it with `git push origin :refs/tags/<tag>` and `git tag -d <tag>`, then tag a commit on `main`.
- **The run fails at "Check the secrets".** The step names each missing secret. Add them to the `release` environment, not the repository.
- **`timestamps differ by N seconds - check your system clock`** when signing locally. `codesign` records the signing time before it shows the Keychain access dialog. Leaving the dialog open for minutes makes that time disagree with Apple's timestamp. Check the clock with `sntp time.apple.com`, then sign again.
- **Notarization ends `Invalid`.** `just notarize` prints the notary log, which lists each problem with its file.
- **`HTTP status code: 403. A required agreement is missing or has expired.`** Apple rejects the upload before notarizing. `just notarize` then fails with `notarytool returned no submission`. This isn't a problem with the zip or the key: the team's Apple Developer Program License Agreement has been updated, or the membership has lapsed. To fix it:
  1. As the Account Holder, sign in at [developer.apple.com/account](https://developer.apple.com/account) and accept the agreement from the banner. Check that the membership is active.
  2. Check App Store Connect → **Business** for any agreement still pending.
  3. Wait a few minutes, then re-run `just notarize <version>`. The signed bundle and zip don't need rebuilding.

  If it still fails, `xcrun notarytool history` with the same key separates account or key problems from problems with the zip.
- **`stapler staple` fails right after `Accepted`.** The ticket can take a moment to propagate. Re-run the job.

## Certificate renewal

The Developer ID certificate, and the original Developer ID CA that issued it, expire on **2027-02-01**. Releases signed before then keep working, because their signatures are timestamped. Signing a new release after that date needs a renewed certificate:

1. Renew the certificate in the Apple Developer portal. It will be issued under the G2 intermediate, which the workflow already imports.
2. Export the new certificate and update `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD`.
3. If the identity's name changed, update `CODESIGN_IDENTITY` in `release.yml`, and the name in this guide and in `CLAUDE.md`.
