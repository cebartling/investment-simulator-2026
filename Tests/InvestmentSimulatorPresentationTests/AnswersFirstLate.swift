import Foundation
import InvestmentSimulatorCore
import Synchronization

/// Answers its first request with `first`, but only once
/// `beforeAnsweringFirst` has run, as a newer request answering first.
/// Answers every later request with `later`.
final class AnswersFirstLate: DailyPriceProviding {
    private let first: Result<[DailyBar], QuoteError>
    private let later: [DailyBar]
    private let count = Mutex(0)
    private let hook = Mutex<(@MainActor @Sendable () async -> Void)?>(nil)

    init(first: Result<[DailyBar], QuoteError>, later: [DailyBar]) {
        self.first = first
        self.later = later
    }

    func beforeAnsweringFirst(_ action: @escaping @MainActor @Sendable () async -> Void) {
        hook.withLock { $0 = action }
    }

    func dailyBars(
        for _: Ticker,
        from _: String,
        through _: String,
        interval _: BarInterval,
    ) async throws(QuoteError) -> [DailyBar] {
        let isFirst = count.withLock { count in
            count += 1
            return count == 1
        }
        guard isFirst else {
            return later
        }
        if let action = hook.withLock({ $0 }) {
            await action()
        }
        return try first.get()
    }
}
