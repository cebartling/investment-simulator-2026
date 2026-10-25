/// Schema version 1 of the `.invsim` file. Money is a decimal string, not a
/// JSON number, so decoding never routes it through `Double` (ADR-0002).
struct ExperimentDocumentV1: Codable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let cashBalance: String
}

/// Reads only the version, to pick the DTO that decodes the rest.
struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int
}
