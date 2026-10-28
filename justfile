app_name := "InvestmentSimulator"
build_dir := "build"
app_bundle := build_dir / "Investment Simulator.app"

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

# Assemble a release .app bundle, ad-hoc signed
bundle:
    swift build -c release
    rm -rf "{{app_bundle}}"
    mkdir -p "{{app_bundle}}/Contents/MacOS" "{{app_bundle}}/Contents/Resources"
    cp "$(swift build -c release --show-bin-path)/{{app_name}}" "{{app_bundle}}/Contents/MacOS/"
    cp Resources/Info.plist "{{app_bundle}}/Contents/"
    xcrun actool "{{justfile_directory()}}/Resources/AppIcon.icon" --compile "{{justfile_directory()}}/{{app_bundle}}/Contents/Resources" --errors --warnings --notices --output-format human-readable-text --platform macosx --minimum-deployment-target "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)" --app-icon AppIcon --output-partial-info-plist "{{justfile_directory()}}/{{build_dir}}/AppIcon-partial.plist"
    test -s "{{app_bundle}}/Contents/Resources/Assets.car" -a -s "{{app_bundle}}/Contents/Resources/AppIcon.icns" || { echo "error: actool wrote no app icon; check Resources/AppIcon.icon" >&2; exit 1; }
    codesign --force --sign - "{{app_bundle}}"
    @echo "Built {{app_bundle}}"

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
