import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ResearchLinkSectionTests {
    private static func release(_ day: String) -> PressRelease {
        PressRelease(
            publishedAt: ISO8601DateFormatter().date(from: "\(day)T11:00:00Z")!,
            title: "Release of \(day)",
            url: URL(string: "https://example.com/\(day)")!,
            summary: nil,
        )
    }

    private static func filing(_ filedDate: String) throws -> Filing {
        try Filing(
            form: "10-Q",
            filedDate: filedDate,
            reportingForDate: nil,
            url: URL(string: "https://example.com/\(filedDate)")!,
        )
    }

    @Test func `press releases load newest first`() async throws {
        let older = Self.release("2026-10-15")
        let newer = Self.release("2026-10-19")
        let tab = try tab(FakeResearchData(
            pressReleases: .success(PressReleases(coverage: .scraped, releases: [older, newer])),
        ))

        await tab.load()

        #expect(tab.pressReleasesState == .loaded([newer, older]))
    }

    @Test(arguments: [PressReleaseCoverage.attempted, .discovered, .untracked])
    func `rows show whatever the coverage`(coverage: PressReleaseCoverage) async throws {
        let rows = [Self.release("2026-10-19")]
        let tab = try tab(FakeResearchData(pressReleases: .success(PressReleases(coverage: coverage, releases: rows))))

        await tab.load()

        #expect(tab.pressReleasesState == .loaded(rows))
    }

    @Test(arguments: [
        (PressReleaseCoverage.scraped, ResearchEmptyReason.nonePublished),
        (.attempted, .notCovered),
        (.discovered, .notCovered),
        (.untracked, .notCovered),
    ])
    func `no press releases read by their coverage`(
        coverage: PressReleaseCoverage,
        expected: ResearchEmptyReason,
    ) async throws {
        let tab = try tab(FakeResearchData(pressReleases: .success(PressReleases(coverage: coverage, releases: []))))

        await tab.load()

        #expect(tab.pressReleasesState == .empty(expected))
    }

    @Test func `no data is empty for press releases and filings`() async throws {
        let tab = try tab(FakeResearchData())

        await tab.load()

        #expect(tab.pressReleasesState == .empty(.noData))
        #expect(tab.filingsState == .empty(.noData))
    }

    @Test func `filings load newest first`() async throws {
        let older = try Self.filing("2026-05-01")
        let newer = try Self.filing("2026-07-31")
        let tab = try tab(FakeResearchData(filings: .success([older, newer])))

        await tab.load()

        #expect(tab.filingsState == .loaded([newer, older]))
    }

    @Test func `a press releases failure leaves filings showing`() async throws {
        let filings = try [Self.filing("2026-07-31")]
        let tab = try tab(FakeResearchData(pressReleases: .failure(.dailyLimitReached), filings: .success(filings)))

        await tab.load()

        #expect(tab.pressReleasesState == .failed(.dailyLimitReached))
        #expect(tab.filingsState == .loaded(filings))
    }

    @Test func `a filings failure leaves press releases showing`() async throws {
        let rows = [Self.release("2026-10-19")]
        let tab = try tab(FakeResearchData(
            pressReleases: .success(PressReleases(coverage: .scraped, releases: rows)),
            filings: .failure(.dailyLimitReached),
        ))

        await tab.load()

        #expect(tab.pressReleasesState == .loaded(rows))
        #expect(tab.filingsState == .failed(.dailyLimitReached))
    }

    private func tab(_ data: FakeResearchData) throws -> ResearchTabModel {
        try ResearchTabModel(
            ticker: Ticker("VTI"),
            quotes: FakeQuotes(.failure(.missingAPIKey)),
            dailyPrices: FakeDailyPrices(),
            profiles: data,
            multiples: data,
            dividends: data,
            pressReleases: data,
            filings: data,
            clock: { Date(timeIntervalSince1970: 1_793_000_000) },
        )
    }
}
