import Foundation

/// Driven port for reading and writing an experiment document (ADR-0005,
/// where it is called `ScenarioCoding`). Synchronous because `FileDocument`
/// reads and writes synchronously.
public protocol ExperimentCoding: Sendable {
    func encode(_ experiment: Experiment) throws -> Data
    func decode(_ data: Data) throws -> Experiment
}
