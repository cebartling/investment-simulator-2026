import Foundation
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
    private let failsToCheck: Mutex<Bool>
    private let failsToRead: Bool
    private let reads = Mutex(0)
    private let readOnMain = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)
    private let isGated: Bool

    init(
        _ email: String? = nil,
        gated: Bool = false,
        failsToSave: Bool = false,
        failsToCheck: Bool = false,
        failsToRead: Bool = false,
    ) {
        self.email = Mutex(email)
        self.failsToSave = failsToSave
        self.failsToCheck = Mutex(failsToCheck)
        self.failsToRead = failsToRead
        isGated = gated
    }

    /// Whether any read of the email itself ran on the main thread.
    var readOnMainThread: Bool {
        readOnMain.withLock { $0 }
    }

    /// Lets a gated read finish, as when the user answers the Keychain prompt.
    func releaseRead() {
        gate.signal()
    }

    /// How many times the email itself was read.
    var readCount: Int {
        reads.withLock { $0 }
    }

    /// Lets later checks succeed, as when the user finally allows Keychain access.
    func allowChecks() {
        failsToCheck.withLock { $0 = false }
    }

    func contactEmail() throws -> String? {
        reads.withLock { $0 += 1 }
        if Thread.isMainThread {
            readOnMain.withLock { $0 = true }
        }
        if isGated {
            gate.wait()
        }
        if failsToRead {
            throw StoreError()
        }
        return email.withLock { $0 }
    }

    func hasContactEmail() throws -> Bool {
        if failsToCheck.withLock({ $0 }) {
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
