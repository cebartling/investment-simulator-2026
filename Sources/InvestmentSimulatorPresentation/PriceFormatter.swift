import Foundation
import InvestmentSimulatorCore

/// Words for an amount of money, such as a price per share, a dividend or a
/// change (PIN-513). Amounts show to the cent, rounded through `Money` with
/// banker's rounding (ADR-0002). Stored amounts keep every decimal, and
/// `full(_:currency:maxDecimals:)` gives the ones rounding hid, for a tooltip.
public struct PriceFormatter {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// To the cent, such as "$342.61" for 342.6138.
    public func cents(_ amount: Decimal, currency: String = "USD") -> String {
        rounded(amount).formatted(style(currency: currency))
    }

    /// A change to the cent with its sign, such as "+$5.94" or "-$0.46".
    /// No change has no sign.
    public func signedCents(_ amount: Decimal) -> String {
        rounded(amount).formatted(style(currency: "USD").sign(strategy: .always(showZero: false)))
    }

    /// The amount with up to `maxDecimals` decimals, such as "$342.6138",
    /// or nil when `cents(_:currency:)` already shows all of it. A quote has
    /// up to 4 decimals (ADR-0012), a dividend up to 6.
    public func full(_ amount: Decimal, currency: String = "USD", maxDecimals: Int = 4) -> String? {
        let full = amount.formatted(
            .currency(code: currency).precision(.fractionLength(2 ... maxDecimals)).locale(locale),
        )
        return full == cents(amount, currency: currency) ? nil : full
    }

    private func rounded(_ amount: Decimal) -> Decimal {
        Money(amount).roundedToCents().amount
    }

    private func style(currency: String) -> Decimal.FormatStyle.Currency {
        .currency(code: currency).precision(.fractionLength(2)).locale(locale)
    }
}
