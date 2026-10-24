// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InvestmentSimulator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "InvestmentSimulatorCore"),
        .target(
            name: "InvestmentSimulatorPresentation",
            // ADR-0003: presentation models are main-actor isolated by default.
            swiftSettings: [.defaultIsolation(MainActor.self)],
        ),
        .executableTarget(
            name: "InvestmentSimulator",
            dependencies: ["InvestmentSimulatorCore", "InvestmentSimulatorPresentation"],
            // ADR-0003: UI code is main-actor isolated by default.
            swiftSettings: [.defaultIsolation(MainActor.self)],
        ),
        .testTarget(
            name: "InvestmentSimulatorCoreTests",
            dependencies: ["InvestmentSimulatorCore"],
        ),
        .testTarget(
            name: "InvestmentSimulatorPresentationTests",
            dependencies: ["InvestmentSimulatorPresentation"],
        ),
    ],
)
