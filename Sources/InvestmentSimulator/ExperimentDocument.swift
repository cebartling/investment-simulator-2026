import InvestmentSimulatorCore
import InvestmentSimulatorPersistence
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Exported in `Resources/Info.plist` with the `.invsim` extension.
    nonisolated static let experiment = UTType(exportedAs: "com.cebartling.InvestmentSimulator.experiment")
}

/// A thin `FileDocument` over the `ExperimentCoding` port; it holds no format
/// knowledge (ADR-0005). `nonisolated` because SwiftUI reads and writes
/// documents off the main actor (ADR-0003).
nonisolated struct ExperimentDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.experiment]

    /// SwiftUI constructs documents itself, so the codec can't be passed in
    /// through an initializer; an immutable static is the composition point.
    private static let codec: any ExperimentCoding = JSONExperimentCodec()

    var experiment: Experiment

    /// True only for a new, untitled document. Not saved.
    let needsSetup: Bool

    init() {
        experiment = .empty
        needsSetup = true
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        experiment = try Self.codec.decode(data)
        needsSetup = false
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: Self.codec.encode(experiment))
    }
}
