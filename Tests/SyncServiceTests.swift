import XCTest
import SwiftData

@MainActor
final class SyncServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: SyncService!

    override func setUp() async throws {
        MockURLProtocol.reset()
        AppSettings.registerDefaults()
        UserDefaults.standard.set(false, forKey: AppSettings.notificationsEnabled)
        UserDefaults.standard.set(false, forKey: AppSettings.automaticChecks)
        UserDefaults.standard.set(false, forKey: AppSettings.ignoreArchived)
        UserDefaults.standard.set(false, forKey: AppSettings.monitorPrerelease)
        let schema = Schema([Repository.self, Release.self, Asset.self, NotificationEvent.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        service = SyncService(
            modelContext: container.mainContext,
            client: GitHubClient(session: MockURLProtocol.session(), tokenProvider: { nil }),
            notifications: StubNotificationService()
        )
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        container = nil
        service = nil
    }

    func testAddBuildsBaselineAndRecognizesMultipleDMGs() async throws {
        let assets = [
            TestFixtures.assetJSON(id: 1, name: "App.dmg"),
            TestFixtures.assetJSON(id: 2, name: "App-arm64.DMG", contentType: "text/plain"),
            TestFixtures.assetJSON(id: 3, name: "App-x64.dmg"),
            TestFixtures.assetJSON(id: 4, name: "App.dmg.sha256")
        ].joined(separator: ",")
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON(assets: assets))]" })

        let outcome = try await service.addRepository(urlString: "https://github.com/octo/Sample/releases/tag/v1.0.0")
        guard case .added(let repository) = outcome else { return XCTFail("应添加新项目") }
        XCTAssertEqual(repository.owner, "octo")
        XCTAssertEqual(repository.latestReleaseID, 100)
        XCTAssertEqual(try service.fetchRepositories().count, 1)
        let releases = try service.fetchReleases(for: 42)
        XCTAssertEqual(releases.count, 1)
        XCTAssertTrue(releases[0].isRead, "首次同步应建立已读基线")
        let savedAssets = try service.fetchAssets(for: 100)
        XCTAssertEqual(savedAssets.count, 4)
        XCTAssertEqual(savedAssets.filter(\.isDMG).count, 3)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<NotificationEvent>()), 0, "首次同步不发送历史通知")
    }

    func testDuplicateRepositoryDoesNotInsert() async throws {
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON())]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Sample")
        let outcome = try await service.addRepository(urlString: "https://github.com/octo/Sample/releases")
        guard case .duplicate(let existing) = outcome else { return XCTFail("应识别重复项目") }
        XCTAssertEqual(existing.id, 42)
        XCTAssertEqual(try service.fetchRepositories().count, 1)
        XCTAssertEqual(try service.fetchReleases(for: 42).count, 1)
    }

    func testNewReleaseCreatesOneDedupedEventAndUpdatesCache() async throws {
        var currentRelease = TestFixtures.releaseJSON(id: 100, tag: "v1.0.0", assets: TestFixtures.assetJSON(id: 1, name: "App.dmg"))
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(currentRelease)]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Sample")

        currentRelease = TestFixtures.releaseJSON(id: 200, tag: "v2.0.0", publishedAt: "2026-02-01T12:00:00Z", assets: TestFixtures.assetJSON(id: 2, name: "App-universal.dmg"))
        await service.refresh(repositoryIDs: [42])
        var events = try container.mainContext.fetch(FetchDescriptor<NotificationEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.releaseID, 200)
        let releases = try service.fetchReleases(for: 42)
        XCTAssertEqual(releases.count, 2)
        XCTAssertFalse(try XCTUnwrap(releases.first { $0.id == 200 }).isRead)
        XCTAssertEqual(try service.fetchAssets(for: 200).count, 1)

        await service.refresh(repositoryIDs: [42])
        events = try container.mainContext.fetch(FetchDescriptor<NotificationEvent>())
        XCTAssertEqual(events.count, 1, "同一 Release 不允许重复通知")
        XCTAssertEqual(try service.fetchReleases(for: 42).count, 2, "刷新不能插入重复 Release")
        XCTAssertEqual(try service.fetchAssets(for: 200).count, 1, "刷新不能插入重复 Asset")
    }

    func testEditingNotesDoesNotCountAsNewVersion() async throws {
        var body = "Initial notes"
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON(body: body))]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Sample")
        body = "Edited notes"
        await service.refresh(repositoryIDs: [42])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<NotificationEvent>()), 0)
        XCTAssertEqual(try service.fetchReleases(for: 42).first?.body, "Edited notes")
    }

    func testNetworkFailurePreservesCachedRelease() async throws {
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON())]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Sample")
        MockURLProtocol.setHandler { _ in throw URLError(.notConnectedToInternet) }
        await service.refresh(repositoryIDs: [42])
        let repository = try XCTUnwrap(service.fetchRepositories().first)
        XCTAssertNotNil(repository.lastError)
        XCTAssertEqual(repository.latestReleaseID, 100)
        XCTAssertEqual(try service.fetchReleases(for: 42).count, 1)
        XCTAssertEqual(try service.fetchAssets(for: 100).count, 0)
    }

    func testNoDMGAndEmptyReleasesRemainVisible() async throws {
        MockURLProtocol.setHandler(TestFixtures.standardHandler { "[\(TestFixtures.releaseJSON(assets: TestFixtures.assetJSON(id: 1, name: "Source.zip")))]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Sample")
        XCTAssertEqual(try service.fetchReleases(for: 42).count, 1)
        XCTAssertEqual(try service.fetchAssets(for: 100).filter(\.isDMG).count, 0)

        MockURLProtocol.setHandler(TestFixtures.standardHandler(repositoryID: 43, name: "Empty") { "[]" })
        _ = try await service.addRepository(urlString: "https://github.com/octo/Empty")
        let empty = try XCTUnwrap(service.fetchRepositories().first { $0.id == 43 })
        XCTAssertNil(empty.latestReleaseID)
        XCTAssertTrue(try service.fetchReleases(for: 43).isEmpty)
    }

    func testMultiProjectRefreshHasBoundedConcurrency() async throws {
        for index in 0..<5 {
            container.mainContext.insert(Repository(
                id: Int64(index + 1),
                owner: "octo",
                name: "Repo\(index)",
                fullName: "octo/Repo\(index)",
                url: "https://github.com/octo/Repo\(index)"
            ))
        }
        try container.mainContext.save()
        let probe = ConcurrencyProbeClient()
        let probingService = SyncService(
            modelContext: container.mainContext,
            client: probe,
            notifications: StubNotificationService()
        )

        await probingService.refresh()
        let maximum = await probe.maximumConcurrentProjects
        XCTAssertEqual(try probingService.fetchRepositories().count, 5)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Release>()), 5)
        XCTAssertEqual(maximum, 3, "同步器应最多同时检查 3 个项目")
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    func testSwiftDataPersistsAcrossContainers() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ReleaseRadarTests-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = Schema([Repository.self, Release.self, Asset.self, NotificationEvent.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        let firstContainer = try ModelContainer(for: schema, configurations: configuration)
        let repository = Repository(id: 77, owner: "octo", name: "Persistent", fullName: "octo/Persistent", url: "https://github.com/octo/Persistent")
        firstContainer.mainContext.insert(repository)
        try firstContainer.mainContext.save()

        let secondContainer = try ModelContainer(for: schema, configurations: configuration)
        let saved = try secondContainer.mainContext.fetch(FetchDescriptor<Repository>())
        XCTAssertEqual(saved.map(\.id), [77])
        XCTAssertEqual(saved.first?.fullName, "octo/Persistent")
    }
}

private final class StubNotificationService: NotificationSending {
    private(set) var newReleaseCount = 0
    private(set) var assetChangeCount = 0

    func sendNewRelease(repository: Repository, release: Release) async -> Bool {
        newReleaseCount += 1
        return false
    }

    func sendAssetChange(repository: Repository, release: Release) async -> Bool {
        assetChangeCount += 1
        return false
    }
}

private actor ConcurrencyProbeClient: GitHubFetching {
    private var activeProjects = 0
    private(set) var maximumConcurrentProjects = 0

    func fetchRepository(owner: String, name: String) async throws -> GitHubRepositoryDTO {
        repositoryDTO(name: name)
    }

    func fetchReleases(owner: String, name: String, page: Int, perPage: Int) async throws -> [GitHubReleaseDTO] {
        [releaseDTO(name: name)]
    }

    func fetchSnapshot(owner: String, name: String) async throws -> GitHubSnapshot {
        activeProjects += 1
        maximumConcurrentProjects = max(maximumConcurrentProjects, activeProjects)
        try? await Task.sleep(for: .milliseconds(120))
        activeProjects -= 1
        return GitHubSnapshot(repository: repositoryDTO(name: name), releases: [releaseDTO(name: name)])
    }

    private func repositoryDTO(name: String) -> GitHubRepositoryDTO {
        let index = Int(name.dropFirst(4)) ?? 0
        return GitHubRepositoryDTO(
            id: Int64(index + 1),
            name: name,
            fullName: "octo/\(name)",
            description: "Concurrency probe",
            htmlURL: "https://github.com/octo/\(name)",
            homepage: nil,
            stargazersCount: 0,
            forksCount: 0,
            language: "Swift",
            topics: [],
            createdAt: nil,
            updatedAt: nil,
            pushedAt: nil,
            archived: false,
            owner: GitHubOwnerDTO(login: "octo", avatarURL: nil)
        )
    }

    private func releaseDTO(name: String) -> GitHubReleaseDTO {
        let index = Int(name.dropFirst(4)) ?? 0
        return GitHubReleaseDTO(
            id: Int64(500 + index),
            tagName: "v1.0.\(index)",
            name: "v1.0.\(index)",
            body: nil,
            htmlURL: "https://github.com/octo/\(name)/releases/tag/v1.0.\(index)",
            publishedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            isDraft: false,
            isPrerelease: false,
            assets: []
        )
    }
}
