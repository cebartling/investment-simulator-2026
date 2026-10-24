import Foundation

/// A USD amount. Wraps `Decimal` so money never passes through `Double`
/// (ADR-0002). Not `Codable`: file formats belong to the persistence adapter.
public struct Money: Sendable, Hashable {
    public static let zero = Money(0)

    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    /// Rounds to whole cents with banker's rounding, for reported figures.
    public func roundedToCents() -> Money {
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .bankers)
        return Money(rounded)
    }
}
