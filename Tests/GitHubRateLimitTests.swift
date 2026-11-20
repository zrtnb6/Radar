import XCTest
import Foundation

final class GitHubRateLimitTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testAnonymousRateLimitDecoding() async throws {
        let json = """
        {"resources":{"core":{"limit":60,"used":5,"remaining":55,"reset":1795024323}},"rate":{"limit":60,"used":5,"remaining":55,"reset":1795024323}}
        """
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/rate_limit")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (mockResponse(url: request.url!), Data(json.utf8))
        }

        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        let status = try await client.fetchRateLimit()

        XCTAssertEqual(status.limit, 60)
        XCTAssertEqual(status.used, 5)
        XCTAssertEqual(status.remaining, 55)
        XCTAssertFalse(status.isAuthenticated)
        XCTAssertEqual(status.reset.timeIntervalSince1970, 1795024323, accuracy: 0.001)
    }

    func testAuthenticatedRateLimitAndBearerHeader() async throws {
        let json = """
        {"rate":{"limit":5000,"used":13,"remaining":4987,"reset":1795024323}}
        """
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_testtoken")
            return (mockResponse(url: request.url!), Data(json.utf8))
        }

        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { "ghp_testtoken" })
        let status = try await client.fetchRateLimit()

        XCTAssertEqual(status.limit, 5000)
        XCTAssertEqual(status.remaining, 4987)
        XCTAssertTrue(status.isAuthenticated)
    }

    func testRateLimitRequestBypassesLocalCache() async throws {
        let json = """
        {"rate":{"limit":60,"used":0,"remaining":60,"reset":1795024323}}
        """
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (mockResponse(url: request.url!), Data(json.utf8))
        }

        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        _ = try await client.fetchRateLimit()
    }

    func testInvalidTokenMapsToUnauthorized() async throws {
        MockURLProtocol.setHandler { request in
            (mockResponse(url: request.url!, status: 401), Data())
        }

        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { "expired" })
        do {
            _ = try await client.fetchRateLimit()
            XCTFail("预期抛出 unauthorized")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRateLimitEndpointIsHTTPS() {
        let url = GitHubEndpoint.rateLimit()
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.github.com")
        XCTAssertEqual(url.path, "/rate_limit")
    }

    func testRateLimitedMessageGuidesTokenSettings() {
        let message = GitHubError.rateLimited(retryAt: nil).errorDescription ?? ""
        XCTAssertTrue(message.contains("60 次"))
        XCTAssertTrue(message.contains("5000 次"))
        XCTAssertTrue(message.contains("GitHub 令牌"))

        let unauthorized = GitHubError.unauthorized.errorDescription ?? ""
        XCTAssertTrue(unauthorized.contains("GitHub 令牌"))
    }
}
