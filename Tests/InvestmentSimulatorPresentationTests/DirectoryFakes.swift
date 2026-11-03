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
    private let writes = Mutex(0)
    private let writeOnMain = Mutex(false)
    private let writeGate = DispatchSemaphore(value: 0)
    private let isWriteGated: Bool

    init(
        _ email: String? = nil,
        gated: Bool = false,
        writeGated: Bool = false,
        failsToSave: Bool = false,
        failsToCheck: Bool = false,
        failsToRead: Bool = false,
    ) {
        self.email = Mutex(email)
        self.failsToSave = failsToSave
        self.failsToCheck = Mutex(failsToCheck)
        self.failsToRead = failsToRead
        isGated = gated
        isWriteGated = writeGated
    }

    /// Whether any read of the email itself ran on the main thread.
    var readOnMainThread: Bool {
        readOnMain.withLock { $0 }
    }

    /// How many times the email was written or removed.
    var writeCount: Int {
        writes.withLock { $0 }
    }

    /// Whether any write ran on the main thread.
    var wroteOnMainThread: Bool {
        writeOnMain.withLock { $0 }
    }

    /// Lets a gated write finish, as when the user answers the Keychain prompt.
    func releaseWrite() {
        writeGate.signal()
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
        // The value is read before the gate, as a slow Keychain answers with
        // what was stored when the read began.
        let value = email.withLock { $0 }
        if isGated {
            try waitForRelease(gate)
        }
        if failsToRead {
            throw StoreError()
        }
        return value
    }

    func hasContactEmail() throws -> Bool {
        if failsToCheck.withLock({ $0 }) {
            throw StoreError()
        }
        return email.withLock { $0 != nil }
    }

    func setContactEmail(_ newEmail: String?) throws {
        writes.withLock { $0 += 1 }
        if Thread.isMainThread {
            writeOnMain.withLock { $0 = true }
        }
        if isWriteGated {
            try waitForRelease(writeGate)
        }
        if failsToSave {
            throw StoreError()
        }
        email.withLock { $0 = newEmail }
    }
}

final class FakeCredentials: CredentialStoring {
    struct StoreError: Error {}

    private let key: Mutex<String?>
    private let failsToSave: Bool
    private let reads = Mutex(0)
    private let writes = Mutex(0)
    private let writeOnMain = Mutex(false)
    private let writeGate = DispatchSemaphore(value: 0)
    private let isWriteGated: Bool

    init(_ key: String? = nil, failsToSave: Bool = false, writeGated: Bool = false) {
        self.key = Mutex(key)
        self.failsToSave = failsToSave
        isWriteGated = writeGated
    }

    /// How many times the key was written or removed.
    var writeCount: Int {
        writes.withLock { $0 }
    }

    /// Whether any write ran on the main thread.
    var wroteOnMainThread: Bool {
        writeOnMain.withLock { $0 }
    }

    /// Lets a gated write finish, as when the user answers the Keychain prompt.
    func releaseWrite() {
        writeGate.signal()
    }

    /// How many times the secret itself was read.
    var keyReadCount: Int {
        reads.withLock { $0 }
    }

    func apiKey() throws -> String? {
        reads.withLock { $0 += 1 }
        return key.withLock { $0 }
    }

    func hasAPIKey() throws -> Bool {
        key.withLock { $0 != nil }
    }

    func setAPIKey(_ newKey: String?) throws {
        writes.withLock { $0 += 1 }
        if Thread.isMainThread {
            writeOnMain.withLock { $0 = true }
        }
        if isWriteGated {
            try waitForRelease(writeGate)
        }
        if failsToSave {
            throw StoreError()
        }
        key.withLock { $0 = newKey }
    }
}

struct GateTimedOut: Error {}

/// Holds a fake Keychain call open until the test releases it. It gives up
/// after a while, so a test that is starved of threads fails instead of
/// hanging the run.
private func waitForRelease(_ gate: DispatchSemaphore) throws {
    if gate.wait(timeout: .now() + 10) == .timedOut {
        throw GateTimedOut()
    }
}
