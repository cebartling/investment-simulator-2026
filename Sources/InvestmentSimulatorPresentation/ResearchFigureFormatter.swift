import Foundation
import InvestmentSimulatorCore

/// Words for a Research section's figures. A figure Equibles didn't send
/// shows as a dash.
public struct ResearchFigureFormatter {
    private static let missing = "—"

    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// A valuation ratio, such as "39.53".
    public func ratio(_ ratio: Decimal?) -> String {
        ratio?.formatted(.number.precision(.fractionLength(2)).locale(locale)) ?? Self.missing
    }

    /// A market cap, rounded for display only, such as "$5.02T".
    public func marketCap(_ marketCap: Money?) -> String {
        marketCap?.amount.formatted(
            .currency(code: "USD").notation(.compactName).precision(.fractionLength(2)).locale(locale),
        ) ?? Self.missing
    }
}
