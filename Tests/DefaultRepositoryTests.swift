import XCTest
import SwiftData

@MainActor
final class DefaultRepositoryTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: DefaultRepository.seedFlagKey)
        MockURLProtocol.reset()
        AppSettings.registerDefaults()
        UserDefaults.standard.set(false, forKey: AppSettings.notificationsEnabled)
        UserDefaults.standard.set(false, forKey: AppSettings.automaticChecks)
        UserDefaults.standard.set(false, forKey: AppSettings.ignoreArchived)
        UserDefaults.standard.set(false, forKey: AppSettings.monitorPrerelease)
        let schema = Schema([Repository.self, Release.self, Asset.self, NotificationEvent.self])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: DefaultRepository.seedFlagKey)
        MockURLProtocol.reset()
        container = nil
    }

    func testSeedsRadarOnEmptyStore() throws {
        XCTAssertTrue(DefaultRepository.seedIfNeeded(context: container.mainContext))

        let repositories = try container.mainContext.fetch(FetchDescriptor<Repository>())
        XCTAssertEqual(repositories.count, 1)
        let repository = try XCTUnwrap(repositories.first)
        XCTAssertEqual(repository.id, DefaultRepository.seedID)
        XCTAssertEqual(repository.owner, "zrtnb6")
        XCTAssertEqual(repository.name, "Radar")
        XCTAssertEqual(repository.fullName, "zrtnb6/Radar")
        XCTAssertEqual(repository.url, "https://github.com/zrtnb6/Radar")
        XCTAssertNil(repository.lastCheckedAt, "预置项目应保持未检查状态，首次刷新才会按基线处理")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: DefaultRepository.seedFlagKey))
    }

    func testSeedIsIdempotent() throws {
        XCTAssertTrue(DefaultRepository.seedIfNeeded(context: container.mainContext))
        XCTAssertFalse(DefaultRepository.seedIfNeeded(context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Repository>()), 1)
    }

    func testDoesNotSeedWhenUserAlreadyHasProjects() throws {
        container.mainContext.insert(Repository(
            id: 42,
            owner: "octo",
            name: "Sample",
            fullName: "octo/Sample",
            url: "https://github.com/octo/Sample"
        ))
        try container.mainContext.save()

        XCTAssertFalse(DefaultRepository.seedIfNeeded(context: container.mainContext))
        let names = try container.mainContext.fetch(FetchDescriptor<Repository>()).map(\.fullName)
        XCTAssertEqual(names, ["octo/Sample"], "升级用户不应被塞入默认项目")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: DefaultRepository.seedFlagKey))
    }

    func testSeedDoesNotReappearAfterUserClearsList() throws {
        XCTAssertTrue(DefaultRepository.seedIfNeeded(context: container.mainContext))
        let repository = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Repository>()).first)
        container.mainContext.delete(repository)
        try container.mainContext.save()

        XCTAssertFalse(DefaultRepository.seedIfNeeded(context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Repository>()), 0, "用户清空列表后不应重新冒出来")
    }

    func testFirstRefreshOfSeededProjectBuildsBaselineWithoutNotification() async throws {
        XCTAssertTrue(DefaultRepository.seedIfNeeded(context: container.mainContext))
        let releasesJSON = "[\(TestFixtures.releaseJSON(assets: TestFixtures.assetJSON(id: 1, name: "Radar.dmg")))]"
        MockURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = url.path.hasSuffix("/releases")
                ? releasesJSON
                : TestFixtures.repositoryJSON(id: 999, owner: "zrtnb6", name: "Radar")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        let service = SyncService(
            modelContext: container.mainContext,
            client: GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil }),
            notifications: NoopNotificationService()
        )

        await service.refresh(repositoryIDs: [DefaultRepository.seedID])

        let repository = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Repository>()).first)
        XCTAssertEqual(repository.fullName, "zrtnb6/Radar")
        XCTAssertEqual(repository.stars, 1234, "首次刷新应补齐真实元数据")
        XCTAssertNotNil(repository.lastCheckedAt)
        XCTAssertNil(repository.lastError)

        let releases = try service.fetchReleases(for: DefaultRepository.seedID)
        XCTAssertEqual(releases.count, 1)
        XCTAssertTrue(releases[0].isRead, "首次刷新只建立已读基线")
        XCTAssertEqual(
            try container.mainContext.fetchCount(FetchDescriptor<NotificationEvent>()),
            0,
            "首次刷新不应把已有 Release 当成新版本推送通知"
        )
    }
}

private final class NoopNotificationService: NotificationSending {
    func sendNewRelease(repository: Repository, release: Release) async -> Bool { false }
    func sendAssetChange(repository: Repository, release: Release) async -> Bool { false }
}
