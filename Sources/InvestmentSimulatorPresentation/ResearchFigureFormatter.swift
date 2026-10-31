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

    /// A company's sector and industry, such as "Technology · Software", or
    /// nil if Equibles sent neither.
    public func classification(of profile: CompanyProfile) -> String? {
        let parts = [profile.sector, profile.industry].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A dividend in its own currency, such as "$0.27" or "$0.0975".
    public func dividendAmount(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(2 ... 4)).locale(locale))
    }

    /// A yield given as a fraction, such as "3.97%" for `0.0397`.
    public func yield(_ yield: Decimal?) -> String {
        yield?.formatted(.percent.precision(.fractionLength(2)).locale(locale)) ?? Self.missing
    }
}
