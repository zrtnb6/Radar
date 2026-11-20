import XCTest

final class GitHubClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRepositoryAndReleaseDecoding() async throws {
        let assets = [TestFixtures.assetJSON(id: 1, name: "App-arm64.dmg"), TestFixtures.assetJSON(id: 2, name: "Source.zip")].joined(separator: ",")
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON(assets: assets))]" })
        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        let repository = try await client.fetchRepository(owner: "octo", name: "Sample")
        let releases = try await client.fetchReleases(owner: "octo", name: "Sample")
        XCTAssertEqual(repository.fullName, "octo/Sample")
        XCTAssertEqual(repository.stargazersCount, 1234)
        XCTAssertEqual(repository.topics, ["macos", "swiftui"])
        XCTAssertEqual(releases.first?.assets.count, 2)
        XCTAssertEqual(releases.first?.publishedAt, ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z"))
    }

    func testPublicRequestsDoNotRequireToken() async throws {
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[]" })
        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        _ = try await client.fetchRepository(owner: "octo", name: "Sample")
        let request = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    func testTokenIsSentOnlyWhenProvided() async throws {
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[]" })
        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { "secret-token" })
        _ = try await client.fetchRepository(owner: "octo", name: "Sample")
        XCTAssertEqual(MockURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testNotFoundAndPrivateErrors() async {
        await assertHTTPError(status: 404, expected: .repositoryNotFound)
        await assertHTTPError(status: 403, headers: ["X-RateLimit-Remaining": "10"], expected: .privateOrForbidden)
        await assertHTTPError(status: 401, expected: .unauthorized)
    }

    func testRateLimitUsesResetDate() async {
        let reset = Date().addingTimeInterval(600)
        await assertHTTPError(
            status: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970))],
            verify: { error in
                guard case GitHubError.rateLimited(let retryAt) = error else { return XCTFail("应为限流错误") }
                XCTAssertEqual(retryAt?.timeIntervalSince1970 ?? 0, reset.timeIntervalSince1970, accuracy: 1)
            }
        )
    }

    func testRetryAfterAndServerError() async {
        await assertHTTPError(status: 429, headers: ["Retry-After": "120"], verify: { error in
            guard case GitHubError.rateLimited(let retryAt) = error else { return XCTFail("应为限流错误") }
            XCTAssertEqual(retryAt?.timeIntervalSinceNow ?? 0, 120, accuracy: 3)
        })
        await assertHTTPError(status: 503, expected: .serverError(503))
    }

    func testNetworkAndDecodingFailures() async {
        MockURLProtocol.setHandler { _ in throw URLError(.timedOut) }
        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        do {
            _ = try await client.fetchRepository(owner: "octo", name: "Sample")
            XCTFail("应抛出超时")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
            XCTAssertTrue(error.userFacingMessage.contains("超时"))
        }

        MockURLProtocol.setHandler { request in
            (mockResponse(url: request.url!), Data("not-json".utf8))
        }
        do {
            _ = try await client.fetchRepository(owner: "octo", name: "Sample")
            XCTFail("应抛出解析错误")
        } catch {
            XCTAssertEqual(error as? GitHubError, .decodingFailed)
        }
    }

    private func assertHTTPError(
        status: Int,
        headers: [String: String]? = nil,
        expected: GitHubError? = nil,
        verify: ((Error) -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        MockURLProtocol.setHandler { request in
            (mockResponse(url: request.url!, status: status, headers: headers), Data("{}".utf8))
        }
        let client = GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil })
        do {
            _ = try await client.fetchRepository(owner: "octo", name: "Sample")
            XCTFail("应返回 HTTP 错误", file: file, line: line)
        } catch {
            if let expected { XCTAssertEqual(error as? GitHubError, expected, file: file, line: line) }
            verify?(error)
        }
    }
}
