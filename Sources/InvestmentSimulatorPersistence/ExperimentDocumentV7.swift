import Foundation

/// Schema version 7 of the `.invsim` file: version 6 plus market sales
/// (ADR-0016). Purchases and orders keep their version 5 shapes.
struct ExperimentDocumentV7: Codable {
    static let schemaVersion = 7

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
    let limitOrders: [LimitOrderV5]
    let buyLimitOrders: [BuyLimitOrderV5]
    let sales: [SaleV7]
    let name: String?
    let notes: String?
    let createdAt: String?
}

/// A market sale. Its price source has the purchase's fields, but only
/// `liveQuote` and `close` are valid.
struct SaleV7: Codable {
    let id: UUID
    let purchaseID: UUID
    let shares: Int
    let pricePerShare: String
    let soldAt: String
    /// `liveQuote` or `close`.
    let priceSource: String
    /// Present for `liveQuote`.
    let delayed: Bool?
    /// Present for `close`.
    let sessionDate: String?
}
