import Foundation

/// Schema version 5 of the `.invsim` file: version 4 plus buy limit orders
/// and cancellations (ADR-0014). Purchases keep the version 2 shape, with
/// `limitOrderFill` added as a price source.
struct ExperimentDocumentV5: Codable {
    static let schemaVersion = 5

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
    let limitOrders: [LimitOrderV5]
    let buyLimitOrders: [BuyLimitOrderV5]
}

struct LimitOrderV5: Codable {
    let id: UUID
    let purchaseID: UUID
    let shares: Int
    let limitPrice: String
    let placedAt: String
    let expiresAt: String
    let filledOn: String?
    /// When the order was cancelled. Absent unless it was.
    let cancelledAt: String?
}

struct BuyLimitOrderV5: Codable {
    /// Also the id of the purchase a fill makes.
    let id: UUID
    let ticker: String
    let shares: Int
    let limitPrice: String
    let placedAt: String
    let expiresAt: String
    let filledOn: String?
    let cancelledAt: String?
}

extension LimitOrderV4 {
    /// The order in version 5, which adds cancellations, as an uncancelled
    /// order.
    var uncancelled: LimitOrderV5 {
        LimitOrderV5(
            id: id,
            purchaseID: purchaseID,
            shares: shares,
            limitPrice: limitPrice,
            placedAt: placedAt,
            expiresAt: expiresAt,
            filledOn: filledOn,
            cancelledAt: nil,
        )
    }
}
