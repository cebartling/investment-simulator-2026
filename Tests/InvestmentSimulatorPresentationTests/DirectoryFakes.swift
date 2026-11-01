import InvestmentSimulatorCore
import Synchronization

/// Answers searches and lookups from `listing`, and records both.
/// `whileAnswering` runs on the main actor during each search.
final class FakeDirectory: SecurityDirectory {
    private let listing: Mutex<Result<[ListedSecurity], MarketDataError>>
    private let searched = Mutex<[String]>([])
    private let lookedUp = Mutex<[Ticker]>([])
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    init(_ listing: Result<[ListedSecurity], MarketDataError> = .success([])) {
        self.listing = Mutex(listing)
    }

    var searches: [String] {
        searched.withLock { $0 }
    }

    var lookups: [Ticker] {
        lookedUp.withLock { $0 }
    }

    func answer(with result: Result<[ListedSecurity], MarketDataError>) {
        listing.withLock { $0 = result }
    }

    func whileAnswering(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func search(_ text: String) async throws(MarketDataError) -> [ListedSecurity] {
        searched.withLock { $0.append(text) }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
        return try listing.withLock { $0 }.get().matching(text)
    }

    func security(for ticker: Ticker) async throws(MarketDataError) -> ListedSecurity? {
        lookedUp.withLock { $0.append(ticker) }
        return try listing.withLock { $0 }.get().security(for: ticker)
    }
}

final class FakeContactEmail: ContactEmailStoring {
    struct StoreError: Error {}

    private let email: Mutex<String?>
    private let failsToSave: Bool
    private let failsToCheck: Bool
    private let reads = Mutex(0)

    init(_ email: String? = nil, failsToSave: Bool = false, failsToCheck: Bool = false) {
        self.email = Mutex(email)
        self.failsToSave = failsToSave
        self.failsToCheck = failsToCheck
    }

    /// How many times the email itself was read.
    var readCount: Int {
        reads.withLock { $0 }
    }

    func contactEmail() throws -> String? {
        reads.withLock { $0 += 1 }
        return email.withLock { $0 }
    }

    func hasContactEmail() throws -> Bool {
        if failsToCheck {
            throw StoreError()
        }
        return email.withLock { $0 != nil }
    }

    func setContactEmail(_ newEmail: String?) throws {
        if failsToSave {
            throw StoreError()
        }
        email.withLock { $0 = newEmail }
    }
}
