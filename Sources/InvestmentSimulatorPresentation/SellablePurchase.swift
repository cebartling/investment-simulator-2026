import Foundation
import InvestmentSimulatorCore

/// A purchase a sell sheet can sell from, with its free shares (PIN-510).
public nonisolated struct SellablePurchase: Identifiable, Hashable, Sendable {
    public let purchase: Purchase
    /// Shares of the purchase neither sold nor in an open sell order.
    public let availableShares: Int

    public var id: UUID {
        purchase.id
    }

    public init(purchase: Purchase, availableShares: Int) {
        self.purchase = purchase
        self.availableShares = availableShares
    }
}

extension [SellablePurchase] {
    /// The purchase a sell sheet starts on: `preferred` when offered, else
    /// the first with free shares, else the first.
    func initialID(preferring preferred: UUID?) -> UUID {
        precondition(!isEmpty, "A sell sheet needs a purchase to sell from")
        if let preferred, contains(where: { $0.id == preferred }) {
            return preferred
        }
        return (first { $0.availableShares > 0 } ?? self[0]).id
    }

    /// The choice `id`. A picker sets only offered ids; any other falls back
    /// to the first.
    func choice(withID id: UUID) -> SellablePurchase {
        first { $0.id == id } ?? self[0]
    }
}
