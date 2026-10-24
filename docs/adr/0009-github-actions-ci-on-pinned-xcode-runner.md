# ADR-0009: GitHub Actions CI on a Pinned Xcode Runner

**Status:** Accepted
**Date:** 2026-10-23
**Deciders:** Christopher Bartling

_This ADR records a decision already in effect (see `.github/workflows/ci.yml` and `CLAUDE.md`). It was written retroactively._

## Context

The app is built and tested only on macOS with a recent Xcode toolchain (macOS 26 deployment target, Swift 6.2, Swift Testing). Linux runners cannot build it, and the default macOS runner images may not carry the Xcode version the project needs.

The project wants CI to run the same commands as a developer, so there is no separate build definition to drift (see ADR-0006). The repository is public on GitHub.

## Decision

- **CI runs on GitHub Actions** (`.github/workflows/ci.yml`) on pushes to `main` and on pull requests.
- **The job runs on the `xcode-27` runner image,** a GitHub public-preview image, and explicitly selects `/Applications/Xcode_27.1.app` with `xcode-select` to match the local toolchain. The image default is Xcode 27.0, which is not used.
- **CI calls the `justfile` recipes,** in this order: `just lint`, `just test`, `just bundle`. A violation, a failing test, or a failed bundle fails the job.
- **Tools are installed with Homebrew** (`just`, `swiftformat`, `swiftlint`), and their versions are printed in the log for diagnosis.
- **Runs for the same ref are de-duplicated:** a `concurrency` group cancels an in-progress run when a newer one starts.
- **Build artifacts are not published yet;** the bundle step only proves the `.app` assembles.
- **Maintenance rule:** when the pinned Xcode is removed from the runner image, update the path in the workflow and the matching note in `CLAUDE.md`.

## Options Considered

### Option A: GitHub Actions on a pinned preview Xcode image (chosen)

**Pros:**
- Matches the local toolchain exactly, including Swift 6.2 and Swift Testing.
- Same `just` commands locally and in CI.
- Built into GitHub with no extra service.

**Cons:**
- A public-preview image can change or disappear, and the pinned Xcode path may vanish without notice.
- macOS runners are slower and costlier than Linux runners.
- Homebrew installs add time and unpinned tool versions (see ADR-0008).

### Option B: Latest stable macOS runner and its default Xcode

**Pros:**
- Most stable and least maintenance.

**Cons:**
- May lack the Xcode version the project needs, causing build failures or toolchain mismatch with local development.

### Option C: Self-hosted macOS runner

**Pros:**
- Full control of Xcode and tool versions; potentially faster.

**Cons:**
- A machine to maintain and secure, and a risk when running pull request code from forks.

### Option D: No CI; check locally only

**Pros:**
- No setup or cost.

**Cons:**
- Nothing stops a broken or unformatted change reaching `main`.

## Consequences

- **Easier:** every change is linted, tested and bundled before merge, in an environment matching local development.
- **Harder:** CI can break for reasons unrelated to the code when the image changes; tool versions are not pinned.
- **Revisit:**
  - Move off the preview image to a stable one when it carries the needed Xcode.
  - Pin `just`, `swiftformat` and `swiftlint` versions.
  - Upload the bundled `.app` as a build artifact, and add signing and notarization steps if distribution happens (see ADR-0006).
  - Cache Homebrew and SwiftPM downloads if CI time becomes a concern.
