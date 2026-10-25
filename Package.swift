// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InvestmentSimulator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "InvestmentSimulatorCore"),
        .target(
            name: "InvestmentSimulatorPresentation",
            dependencies: ["InvestmentSimulatorCore"],
            // ADR-0003: presentation models are main-actor isolated by default.
            swiftSettings: [.defaultIsolation(MainActor.self)],
        ),
        .target(
            name: "InvestmentSimulatorPersistence",
            dependencies: ["InvestmentSimulatorCore"],
        ),
        .executableTarget(
            name: "InvestmentSimulator",
            dependencies: [
                "InvestmentSimulatorCore",
                "InvestmentSimulatorPersistence",
                "InvestmentSimulatorPresentation",
            ],
            // ADR-0003: UI code is main-actor isolated by default.
            swiftSettings: [.defaultIsolation(MainActor.self)],
        ),
        .testTarget(
            name: "InvestmentSimulatorCoreTests",
            dependencies: ["InvestmentSimulatorCore"],
        ),
        .testTarget(
            name: "InvestmentSimulatorPersistenceTests",
            dependencies: ["InvestmentSimulatorCore", "InvestmentSimulatorPersistence"],
        ),
        .testTarget(
            name: "InvestmentSimulatorPresentationTests",
            dependencies: ["InvestmentSimulatorCore", "InvestmentSimulatorPresentation"],
        ),
    ],
)
