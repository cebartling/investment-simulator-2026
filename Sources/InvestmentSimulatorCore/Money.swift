import Foundation

/// A USD amount. Wraps `Decimal` so money never passes through `Double`
/// (ADR-0002). Not `Codable`: file formats belong to the persistence adapter.
public struct Money: Sendable, Hashable {
    public static let zero = Money(0)

    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    /// The amount times a whole count, such as a share price times shares.
    /// Not rounded.
    public func times(_ count: Int) -> Money {
        Money(amount * Decimal(count))
    }

    /// Rounds to whole cents with banker's rounding, for reported figures.
    public func roundedToCents() -> Money {
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .bankers)
        return Money(rounded)
    }

    /// Rounds up to whole cents, for a target price that must not fall short.
    public func roundedUpToCents() -> Money {
        var source = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .up)
        return Money(rounded)
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }
}

/// Arithmetic. Results are not rounded.
public extension Money {
    static func + (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount + rhs.amount)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount - rhs.amount)
    }
}
