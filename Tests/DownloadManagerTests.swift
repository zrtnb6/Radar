import XCTest
import Foundation

final class DownloadPolicyTests: XCTestCase {
    private let validURL = "https://github.com/octo/Sample/releases/download/v1/App.dmg"

    func testAcceptsGitHubHTTPSDirectLinks() throws {
        XCTAssertNoThrow(try DownloadPolicy.validatedURL(validURL))
        XCTAssertNoThrow(try DownloadPolicy.validatedURL("https://www.github.com/octo/Sample/releases/download/v1/App.DMG?x=1"))
        let url = try DownloadPolicy.validatedURL(validURL)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.scheme, "https")
    }

    func testRejectsUnsafeURLs() {
        let invalid = [
            "http://github.com/octo/Sample/releases/download/v1/App.dmg",
            "https://evil.com/octo/Sample/releases/download/v1/App.dmg",
            "https://github.com.evil.com/App.dmg",
            "ftp://github.com/App.dmg",
            "javascript:alert(1)",
            "https://user:pass@github.com/octo/Sample/App.dmg",
            "not a url",
            ""
        ]
        for raw in invalid {
            XCTAssertThrowsError(try DownloadPolicy.validatedURL(raw), "应拒绝: \(raw)") { error in
                XCTAssertEqual(error as? DownloadError, DownloadError.invalidURL)
            }
        }
    }

    func testSanitizesFileName() {
        XCTAssertEqual(DownloadPolicy.sanitizedFileName("App-arm64.DMG"), "App-arm64.DMG")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName("../../evil.dmg"), "evil.dmg")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName("folder/App.dmg"), "App.dmg")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName("App:beta.dmg"), "App_beta.dmg")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName(""), "Radar-Download")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName(".."), "Radar-Download")
        XCTAssertEqual(DownloadPolicy.sanitizedFileName(".hidden"), "Radar-Download")
    }

    func testDestinationDoesNotOverwriteExistingFiles() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(DownloadPolicy.destinationURL(for: "App.dmg", in: directory).lastPathComponent, "App.dmg")

        try Data("old".utf8).write(to: directory.appendingPathComponent("App.dmg"))
        XCTAssertEqual(DownloadPolicy.destinationURL(for: "App.dmg", in: directory).lastPathComponent, "App 2.dmg")

        try Data("old2".utf8).write(to: directory.appendingPathComponent("App 2.dmg"))
        XCTAssertEqual(DownloadPolicy.destinationURL(for: "App.dmg", in: directory).lastPathComponent, "App 3.dmg")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("App.dmg")), Data("old".utf8))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rr-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class DownloadManagerTests: XCTestCase {
    private let validURL = "https://github.com/octo/Sample/releases/download/v1/App.dmg"

    func testDownloadWritesFileAndMarksCompleted() async throws {
        let directory = try makeTempDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let payload = Data("hello-releaseradar".utf8)
        let manager = makeManager(directory: directory) { request in
            (mockResponse(url: request.url!, headers: ["Content-Length": "\(payload.count)"]), payload)
        }

        manager.start(asset: makeAsset(id: 7_001))
        await waitFor { manager.items[7_001]?.state == .completed }

        let item = manager.items[7_001]
        XCTAssertEqual(item?.state, .completed)
        XCTAssertEqual(item?.progress ?? 0, 1.0, accuracy: 0.001)
        let file = directory.appendingPathComponent("App.dmg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: file), payload)
        XCTAssertEqual(manager.activeCount, 0)
    }

    func testHTTPErrorMarksFailedAndDoesNotWriteFile() async throws {
        let directory = try makeTempDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = makeManager(directory: directory) { request in
            (mockResponse(url: request.url!, status: 500), Data("server error".utf8))
        }

        manager.start(asset: makeAsset(id: 7_002))
        await waitFor { manager.items[7_002]?.state == .failed }

        let item = manager.items[7_002]
        XCTAssertEqual(item?.state, .failed)
        XCTAssertTrue(item?.errorMessage?.contains("500") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("App.dmg").path))
    }

    func testInvalidURLFailsWithoutNetworkRequest() async throws {
        let directory = try makeTempDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = makeManager(directory: directory) { request in
            (mockResponse(url: request.url!), Data())
        }
        let asset = makeAsset(id: 7_003, url: "http:// evil.com/App.dmg")

        manager.start(asset: asset)
        await waitFor { manager.items[7_003]?.state == .failed }

        XCTAssertEqual(manager.items[7_003]?.state, .failed)
        XCTAssertTrue(MockURLProtocol.recordedRequests.isEmpty, "非法地址不应发起网络请求")
    }

    func testRetryCreatesFreshItem() async throws {
        let directory = try makeTempDirectory()
        defer {
            MockURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let payload = Data("retry-ok".utf8)
        let manager = makeManager(directory: directory) { request in
            (mockResponse(url: request.url!, headers: ["Content-Length": "\(payload.count)"]), payload)
        }
        let asset = makeAsset(id: 7_004)

        manager.start(asset: asset)
        await waitFor { manager.items[7_004]?.state == .completed }
        manager.retry(asset: asset)
        await waitFor { manager.items[7_004]?.state == .completed }

        XCTAssertEqual(manager.items[7_004]?.state, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("App 2.dmg").path))
    }

    private func makeManager(
        directory: URL,
        handler: @escaping MockURLProtocol.Handler
    ) -> DownloadManager {
        MockURLProtocol.reset()
        MockURLProtocol.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return DownloadManager(configuration: configuration, downloadsDirectory: directory)
    }

    private func makeAsset(id: Int64, name: String = "App.dmg", url: String? = nil) -> Asset {
        Asset(
            id: id,
            releaseID: id,
            name: name,
            size: 18,
            contentType: "application/octet-stream",
            downloadURL: url ?? validURL,
            isDMG: true
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rr-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
