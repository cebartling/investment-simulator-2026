app_name := "InvestmentSimulator"
build_dir := "build"
app_bundle := build_dir / "Investment Simulator.app"
release_zip_prefix := build_dir / "Investment-Simulator-"

# "-" signs ad-hoc; a Developer ID identity also enables hardened runtime and a secure timestamp
identity := env("CODESIGN_IDENTITY", "-")

# List available recipes
default:
    @just --list

# Compile a debug build
build:
    swift build

# Run the test suite
test:
    swift test

# Launch the app straight from SwiftPM (debug, no .app bundle)
run:
    swift run {{app_name}}

# Assemble a release .app bundle, signed with CODESIGN_IDENTITY (ad-hoc by default); version and build stamp the bundled Info.plist
bundle version="" build="":
    @if [ -n "{{version}}{{build}}" ]; then \
        echo "{{version}}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "error: version must be MAJOR.MINOR.PATCH, got '{{version}}'" >&2; exit 1; }; \
        echo "{{build}}" | grep -Eq '^[1-9][0-9]*$' || { echo "error: build must be a positive integer, got '{{build}}'" >&2; exit 1; }; \
    fi
    swift build -c release
    rm -rf "{{app_bundle}}"
    mkdir -p "{{app_bundle}}/Contents/MacOS" "{{app_bundle}}/Contents/Resources"
    cp "$(swift build -c release --show-bin-path)/{{app_name}}" "{{app_bundle}}/Contents/MacOS/"
    cp Resources/Info.plist "{{app_bundle}}/Contents/"
    xcrun actool "{{justfile_directory()}}/Resources/AppIcon.icon" --compile "{{justfile_directory()}}/{{app_bundle}}/Contents/Resources" --errors --warnings --notices --output-format human-readable-text --platform macosx --minimum-deployment-target "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)" --app-icon AppIcon --output-partial-info-plist "{{justfile_directory()}}/{{build_dir}}/AppIcon-partial.plist"
    test -s "{{app_bundle}}/Contents/Resources/Assets.car" -a -s "{{app_bundle}}/Contents/Resources/AppIcon.icns" || { echo "error: actool wrote no app icon; check Resources/AppIcon.icon" >&2; exit 1; }
    if [ -n "{{version}}" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {{version}}" -c "Set :CFBundleVersion {{build}}" "{{app_bundle}}/Contents/Info.plist"; fi
    codesign --force {{ if identity == "-" { "" } else { "--options runtime --timestamp " } }}--sign "{{identity}}" "{{app_bundle}}"
    @echo "Built {{app_bundle}}"

# Zip the bundled .app for a GitHub Release
release-zip version:
    rm -f "{{release_zip_prefix}}{{version}}.zip"
    ditto -c -k --sequesterRsrc --keepParent "{{app_bundle}}" "{{release_zip_prefix}}{{version}}.zip"

# Notarize the release zip, staple the ticket to the .app, check it with Gatekeeper, and re-zip it
notarize version:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH to the App Store Connect API key (.p8) file}"
    : "${NOTARY_KEY_ID:?set NOTARY_KEY_ID to the App Store Connect API key ID}"
    : "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID to the App Store Connect issuer ID}"
    zip="{{release_zip_prefix}}{{version}}.zip"
    test -f "$zip" || { echo "error: $zip not found; run just release-zip {{version}} first" >&2; exit 1; }
    auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    # notarytool exits non-zero for an Invalid submission; read its result anyway so the log gets printed.
    result=$(xcrun notarytool submit "$zip" "${auth[@]}" --wait --output-format json) || true
    id=$(plutil -extract id raw -o - - <<< "$result" 2> /dev/null) || {
        echo "error: notarytool returned no submission for $zip: $result" >&2
        exit 1
    }
    status=$(plutil -extract status raw -o - - <<< "$result")
    if [ "$status" != "Accepted" ]; then
        echo "error: notarization of $zip ended with status '$status' (submission $id)" >&2
        xcrun notarytool log "$id" "${auth[@]}" >&2
        exit 1
    fi
    # The uploaded zip has no ticket, so staple the .app and zip it again.
    xcrun stapler staple "{{app_bundle}}"
    xcrun stapler validate "{{app_bundle}}"
    spctl --assess --type execute -vv "{{app_bundle}}"
    "{{just_executable()}}" --justfile "{{justfile()}}" release-zip "{{version}}"

# Build the .app bundle and open it
open: bundle
    open "{{app_bundle}}"

# Format sources in place
format:
    swiftformat Sources Tests Package.swift

# Check formatting and lint without modifying files
lint:
    swiftformat Sources Tests Package.swift --lint
    swiftlint lint --strict Sources Tests Package.swift

# Remove build artifacts
clean:
    swift package clean
    rm -rf {{build_dir}}
