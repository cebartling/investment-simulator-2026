# ADR-0017: App Icon from an Icon Composer Source

**Status:** Accepted
**Date:** 2026-10-28
**Deciders:** Christopher Bartling

## Context

The app had no icon. ADR-0006 assembles the `.app` by hand from SwiftPM, so nothing compiles an asset catalog, and its Consequences list icons among the things Xcode would otherwise automate. The Dock, Finder, the App Switcher, the About panel and any released download showed the generic app icon.

On macOS 26, icons use Liquid Glass and come in default, dark, tinted and clear styles. A flat `.icns` gets none of those and sits inside a gray legacy squircle.

## Decision

- **The icon source is an Icon Composer document, `Resources/AppIcon.icon`:** `icon.json` plus flat SVG layers under `Assets/`. It is edited in Icon Composer (shipped inside Xcode.app), or by hand for the SVGs, and committed like other source.
- **`just bundle` compiles it with `xcrun actool`** into `Contents/Resources/Assets.car` and an `AppIcon.icns` fallback, before `codesign`, so the signature seals them. `actool` gets absolute paths, because it resolves relative ones against the directory its compile service started in. Its partial `Info.plist` goes to `build/` and isn't merged.
- **`Info.plist` names the icon with fixed keys:** `CFBundleIconName` and `CFBundleIconFile`, both `AppIcon`, matching `actool`'s partial plist and its `--app-icon` argument. If any of the three changes, all must change together.
- **`swift run` keeps the generic icon.** It runs the bare executable without a bundle.

## Options Considered

### Option A: Icon Composer `.icon` compiled by `actool`

**Pros:**
- Liquid Glass with default, dark, tinted and clear styles, from one source.
- No pre-rendered bitmaps in the repo; `Assets.car` is a build product, like the binary.
- `actool` ships with Xcode, which the build already requires, and on CI's `xcode-27` runner.

**Cons:**
- The `icon.json` format belongs to Apple and may change between Xcode releases.
- Glass, translucency and appearance settings are only practical to tune in Icon Composer.

### Option B: Hand-maintained `.icns` from `iconutil`

**Pros:**
- A long-stable format, with no `actool` step.

**Cons:**
- No Liquid Glass or appearance variants; macOS 26 shows it in the legacy squircle.
- Every size is a committed bitmap to regenerate on each change.

### Option C: An `.xcassets` AppIcon set compiled by `actool`

**Pros:**
- Familiar asset-catalog format.

**Cons:**
- Still bitmaps per size, and no Liquid Glass layers.

## Consequences

- **Easier:** changing the icon is an edit to `Resources/AppIcon.icon` and a rebuild; no code changes.
- **Harder:** `just bundle` now depends on `actool` accepting the `.icon` format of the selected Xcode.
- **Revisit:**
  - A dedicated `.invsim` document icon; Finder derives one from the app icon for now.
  - The `actool` invocation if an Xcode update changes the `.icon` format or its output.
