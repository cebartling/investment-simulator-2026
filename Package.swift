// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InvestmentSimulator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "InvestmentSimulatorCore"),
        .executableTarget(
            name: "InvestmentSimulator",
            dependencies: ["InvestmentSimulatorCore"]
        ),
        .testTarget(
            name: "InvestmentSimulatorCoreTests",
            dependencies: ["InvestmentSimulatorCore"]
        ),
    ]
)
