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
