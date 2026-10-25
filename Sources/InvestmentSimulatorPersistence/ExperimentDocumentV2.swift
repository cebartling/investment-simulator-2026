import Foundation

/// Schema version 2 of the `.invsim` file: version 1 plus purchases. Money
/// and prices are decimal strings, and dates ISO 8601 strings.
struct ExperimentDocumentV2: Codable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
}

struct PurchaseV2: Codable {
    let id: UUID
    let ticker: String
    let shares: Int
    let pricePerShare: String
    let pricedAt: String
    /// `liveQuote`, with `delayed`, or `close`, with `sessionDate`.
    let priceSource: String
    let delayed: Bool?
    let sessionDate: String?
}
