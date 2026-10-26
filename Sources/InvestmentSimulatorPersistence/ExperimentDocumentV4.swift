import Foundation

/// Schema version 4 of the `.invsim` file: version 3 plus limit-order fills.
/// Purchases are unchanged from version 2.
struct ExperimentDocumentV4: Codable {
    static let schemaVersion = 4

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
    let limitOrders: [LimitOrderV4]
}

struct LimitOrderV4: Codable {
    let id: UUID
    let purchaseID: UUID
    let shares: Int
    let limitPrice: String
    let placedAt: String
    /// Stored, so a later change to how long orders last leaves this one alone.
    let expiresAt: String
    /// The `yyyy-MM-dd` session the order filled in at its limit price.
    /// Absent while unfilled.
    let filledOn: String?
}
