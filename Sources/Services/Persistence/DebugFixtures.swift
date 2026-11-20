#if DEBUG
import Darwin
import Foundation
import SwiftData

enum DebugFixtures {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RELEASERADAR_UI_FIXTURES"] == "1" ||
            CommandLine.arguments.contains("--ui-fixtures") ||
            UserDefaults.standard.bool(forKey: "DebugUIFixtures")
    }

    // MARK: - 内置下载器视觉验收（DEBUG only，不进入 Release）

    static var downloadDemoEnabled: Bool {
        UserDefaults.standard.bool(forKey: "DebugDownloadDemo") ||
            ProcessInfo.processInfo.environment["RELEASERADAR_UI_DOWNLOAD_DEMO"] == "1"
    }

    static var autoDownloadDemoEnabled: Bool {
        downloadDemoEnabled && UserDefaults.standard.bool(forKey: "DebugAutoDownloadDemo")
    }

    static var demoDownloadsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("releaseradar-downloads", isDirectory: true)
    }

    static var demoDownloadsDirectoryIfEnabled: URL? {
        downloadDemoEnabled ? demoDownloadsDirectory : nil
    }

    static func prepareDemoDownloadsDirectory() {
        guard downloadDemoEnabled else { return }
        let directory = demoDownloadsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        existing.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    static func downloadSessionConfiguration() -> URLSessionConfiguration? {
        guard downloadDemoEnabled else { return nil }
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [DebugDownloadURLProtocol.self]
        return configuration
    }

    static func populate(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Repository>())) == 0 else { return }
        let now = Date()

        let orbit = Repository(
            id: 900_001,
            owner: "lumen-labs",
            name: "Orbit",
            fullName: "lumen-labs/Orbit",
            url: "https://github.com/lumen-labs/Orbit",
            repositoryDescription: "Keyboard-first window management for macOS.",
            homepage: "https://example.com/orbit",
            stars: 8_420,
            forks: 312,
            language: "Swift",
            topics: ["macos", "window-management"],
            isArchived: false,
            addedAt: now.addingTimeInterval(-86_400 * 12),
            lastCheckedAt: now.addingTimeInterval(-420),
            latestReleaseID: 910_004
        )
        orbit.latestReleaseID = 910_004

        let mono = Repository(
            id: 900_002,
            owner: "inkstone",
            name: "Mono",
            fullName: "inkstone/Mono",
            url: "https://github.com/inkstone/Mono",
            repositoryDescription: "A focused Markdown workspace with native typography.",
            stars: 3_120,
            forks: 147,
            language: "Swift",
            topics: ["markdown", "writing"],
            addedAt: now.addingTimeInterval(-86_400 * 8),
            lastCheckedAt: now.addingTimeInterval(-3_600),
            latestReleaseID: 910_031
        )

        let harbor = Repository(
            id: 900_003,
            owner: "northstar",
            name: "Harbor",
            fullName: "northstar/Harbor",
            url: "https://github.com/northstar/Harbor",
            repositoryDescription: "Self-hosted build cache and artifact inspector.",
            stars: 1_908,
            forks: 86,
            language: "Go",
            topics: ["build", "developer-tools"],
            addedAt: now.addingTimeInterval(-86_400 * 20),
            lastCheckedAt: now.addingTimeInterval(-7_200),
            latestReleaseID: 910_002
        )

        let beacon = Repository(
            id: 900_004,
            owner: "field-notes",
            name: "Beacon",
            fullName: "field-notes/Beacon",
            url: "https://github.com/field-notes/Beacon",
            repositoryDescription: "Lightweight status monitoring for small teams.",
            stars: 640,
            forks: 31,
            language: "TypeScript",
            topics: ["monitoring"],
            addedAt: now.addingTimeInterval(-86_400 * 2),
            lastCheckedAt: now.addingTimeInterval(-18_000),
            lastError: "网络请求超时，请检查连接后重试。"
        )

        [orbit, mono, harbor, beacon].forEach(context.insert)

        let release4 = Release(
            id: 910_004,
            repositoryID: orbit.id,
            tagName: "v2.4.0",
            name: "Orbit 2.4",
            body: """
            ## What's new

            - **Snap layouts** now support three-column workspaces.
            - New keyboard shortcut editor with conflict detection.
            - Faster window restoration after display changes.

            ### Fixes

            Fixed a rare issue where floating windows could move between Spaces.
            """,
            htmlURL: "https://github.com/lumen-labs/Orbit/releases/tag/v2.4.0",
            publishedAt: now.addingTimeInterval(-7_800),
            createdAt: now.addingTimeInterval(-7_800),
            updatedAt: now.addingTimeInterval(-4_200),
            isRead: false
        )
        let release3 = Release(
            id: 910_003,
            repositoryID: orbit.id,
            tagName: "v2.3.1",
            name: "Orbit 2.3.1",
            body: "Maintenance release with stability improvements.",
            htmlURL: "https://github.com/lumen-labs/Orbit/releases/tag/v2.3.1",
            publishedAt: now.addingTimeInterval(-86_400 * 26),
            createdAt: now.addingTimeInterval(-86_400 * 26),
            updatedAt: now.addingTimeInterval(-86_400 * 26),
            isRead: true
        )
        let monoRelease = Release(
            id: 910_031,
            repositoryID: mono.id,
            tagName: "v1.8.1",
            name: "Mono 1.8.1",
            body: "Improved table rendering and export performance.",
            htmlURL: "https://github.com/inkstone/Mono/releases/tag/v1.8.1",
            publishedAt: now.addingTimeInterval(-86_400 * 4),
            createdAt: now.addingTimeInterval(-86_400 * 4),
            updatedAt: now.addingTimeInterval(-86_400 * 4),
            isRead: true
        )
        let harborRelease = Release(
            id: 910_002,
            repositoryID: harbor.id,
            tagName: "v0.9.7",
            name: "Harbor 0.9.7",
            body: "Command-line only release. Docker and source archives are attached.",
            htmlURL: "https://github.com/northstar/Harbor/releases/tag/v0.9.7",
            publishedAt: now.addingTimeInterval(-86_400 * 9),
            createdAt: now.addingTimeInterval(-86_400 * 9),
            updatedAt: now.addingTimeInterval(-86_400 * 9),
            isRead: true
        )
        [release4, release3, monoRelease, harborRelease].forEach(context.insert)

        let assets = [
            Asset(id: 920_001, releaseID: release4.id, name: "Orbit-2.4.0-universal.dmg", size: 18_500_000, contentType: "application/x-apple-diskimage", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0-universal.dmg", downloadCount: 2_300, isDMG: true),
            Asset(id: 920_002, releaseID: release4.id, name: "Orbit-2.4.0-arm64.dmg", size: 12_100_000, contentType: "application/octet-stream", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0-arm64.dmg", downloadCount: 940, isDMG: true),
            Asset(id: 920_003, releaseID: release4.id, name: "Orbit-2.4.0.zip", size: 20_300_000, contentType: "application/zip", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0.zip", downloadCount: 130, isDMG: false),
            Asset(id: 920_004, releaseID: monoRelease.id, name: "Mono-1.8.1.dmg", size: 9_400_000, contentType: "application/octet-stream", downloadURL: "https://github.com/inkstone/Mono/releases/download/v1.8.1/Mono-1.8.1.dmg", downloadCount: 680, isDMG: true),
            Asset(id: 920_005, releaseID: harborRelease.id, name: "harbor_0.9.7_linux_arm64.tar.gz", size: 8_200_000, contentType: "application/gzip", downloadURL: "https://github.com/northstar/Harbor/releases/download/v0.9.7/harbor_0.9.7_linux_arm64.tar.gz", downloadCount: 51, isDMG: false)
        ]
        assets.forEach(context.insert)

        context.insert(NotificationEvent(id: "release:\(orbit.id):\(release4.id)", repositoryID: orbit.id, releaseID: release4.id, isDelivered: true))
        try? context.save()
    }
}

/// 视觉验收专用：把下载流量拦截在进程内，不访问网络，文件只写入临时目录。
final class DebugDownloadURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let chunkSize = 120_000
        let chunks = 24
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(chunkSize * chunks)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = Data(repeating: 0x41, count: chunkSize)
        for _ in 0..<chunks {
            client?.urlProtocol(self, didLoad: chunk)
            usleep(90_000)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
