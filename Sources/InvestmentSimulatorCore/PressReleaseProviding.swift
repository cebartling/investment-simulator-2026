import Foundation

/// One release from a company's investor relations site.
public struct PressRelease: Sendable, Hashable {
    public let publishedAt: Date
    public let title: String
    public let url: URL
    public let summary: String?

    public init(publishedAt: Date, title: String, url: URL, summary: String?) {
        self.publishedAt = publishedAt
        self.title = title
        self.url = url
        self.summary = summary
    }
}

/// How far Equibles has got with a company's investor relations site.
public enum PressReleaseCoverage: Sendable, Hashable {
    /// Read, so an empty list means nothing was published.
    case scraped
    /// Tried, without getting any releases.
    case attempted
    /// Found, but not read yet.
    case discovered
    /// Unknown to Equibles, or a status the app doesn't know.
    case untracked
}

/// A ticker's press releases, with how far to trust an empty list.
public struct PressReleases: Sendable, Hashable {
    public let coverage: PressReleaseCoverage
    public let releases: [PressRelease]

    public init(coverage: PressReleaseCoverage, releases: [PressRelease]) {
        self.coverage = coverage
        self.releases = releases
    }
}

/// Driven port for a ticker's press releases (ADR-0019). `async` because
/// adapters reach the network (ADR-0003).
public protocol PressReleaseProviding: Sendable {
    func pressReleases(for ticker: Ticker) async throws(MarketDataError) -> PressReleases
}
