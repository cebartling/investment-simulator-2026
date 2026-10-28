import Foundation

/// Schema version 6 of the `.invsim` file: version 5 plus the experiment's
/// name, notes and created date (PIN-408). Purchases and orders keep their
/// version 5 shapes.
struct ExperimentDocumentV6: Codable {
    static let schemaVersion = 6

    let schemaVersion: Int
    let cashBalance: String
    let purchases: [PurchaseV2]
    let limitOrders: [LimitOrderV5]
    let buyLimitOrders: [BuyLimitOrderV5]
    /// Absent unless the user named the experiment.
    let name: String?
    /// Absent unless the experiment has notes.
    let notes: String?
    /// Absent when an older file had no purchases or orders to date it by.
    let createdAt: String?
}
