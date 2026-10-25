import Foundation
import InvestmentSimulatorCore
import Synchronization
import Testing

/// Answers every quote request with `result`.
final class FakeQuotes: QuoteProviding {
    private let result: Mutex<Result<Quote, QuoteError>>
    private let count = Mutex(0)

    init(_ result: Result<Quote, QuoteError>) {
        self.result = Mutex(result)
    }

    var requestCount: Int {
        count.withLock { $0 }
    }

    func answer(with newResult: Result<Quote, QuoteError>) {
        result.withLock { $0 = newResult }
    }

    func quote(for _: Ticker) async throws(QuoteError) -> Quote {
        count.withLock { $0 += 1 }
        return try result.withLock { $0 }.get()
    }
}

final class FakeCredentials: CredentialStoring {
    struct StoreError: Error {}

    private let key: Mutex<String?>
    private let failsToSave: Bool

    init(_ key: String? = nil, failsToSave: Bool = false) {
        self.key = Mutex(key)
        self.failsToSave = failsToSave
    }

    func apiKey() throws -> String? {
        key.withLock { $0 }
    }

    func setAPIKey(_ newKey: String?) throws {
        if failsToSave {
            throw StoreError()
        }
        key.withLock { $0 = newKey }
    }
}

func makeQuote(price: String, source: PriceSource = .liveQuote(delayed: true)) throws -> Quote {
    try Quote(
        ticker: Ticker("VTI"),
        price: #require(Decimal(string: price)),
        asOf: Date(timeIntervalSince1970: 1_793_000_000),
        source: source,
    )
}

let fixedPurchaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
