import Foundation

/// Schema version 3 of the `.invsim` file: version 2 plus limit orders.
/// Purchases are unchanged from version 2.
struct ExperimentDocumentV3: Codable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
    let limitOrders: [LimitOrderV3]
}

struct LimitOrderV3: Codable {
    let id: UUID
    let purchaseID: UUID
    let shares: Int
    let limitPrice: String
    let placedAt: String
    /// Stored, so a later change to how long orders last leaves this one alone.
    let expiresAt: String
}
