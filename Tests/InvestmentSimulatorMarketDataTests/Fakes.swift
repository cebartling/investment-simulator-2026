import Foundation
import InvestmentSimulatorCore
import InvestmentSimulatorMarketData
import Synchronization
import Testing

/// Answers each request from canned responses keyed by URL path plus query,
/// such as `/v1/x?offset=2`, or else by path alone, and records the
/// requests it was sent.
final class FakeTransport: HTTPTransport {
    private let responses: [String: (status: Int, body: String)]
    private let sent = Mutex<[URLRequest]>([])
    private let failure: URLError?

    init(_ responses: [String: (status: Int, body: String)] = [:], failure: URLError? = nil) {
        self.responses = responses
        self.failure = failure
    }

    var requests: [URLRequest] {
        sent.withLock { $0 }
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.withLock { $0.append(request) }
        if let failure {
            throw failure
        }
        let url = try #require(request.url)
        let pathAndQuery = url.query().map { "\(url.path())?\($0)" }
        let (status, body) = pathAndQuery.flatMap { responses[$0] } ?? responses[url.path()] ?? (500, "")
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }
}

final class FakeCredentials: CredentialStoring {
    private let key: Mutex<String?>

    init(_ key: String?) {
        self.key = Mutex(key)
    }

    func apiKey() throws -> String? {
        key.withLock { $0 }
    }

    func hasAPIKey() throws -> Bool {
        key.withLock { $0 != nil }
    }

    func setAPIKey(_ newKey: String?) throws {
        key.withLock { $0 = newKey }
    }
}
