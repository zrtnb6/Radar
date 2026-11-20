import XCTest

final class ReleaseDetectorTests: XCTestCase {
    func testDMGExtensionCaseInsensitive() {
        ["App.dmg", "App-Universal.dmg", "App-arm64.dmg", "App-x64.DMG", "App.DmG"].forEach {
            XCTAssertTrue(ReleaseDetector.isDMG(fileName: $0), $0)
        }
    }

    func testRejectsNonDMGAndNestedSuffixes() {
        ["App.zip", "App.dmg.sha256", "Appdmg", "App.dmg.txt", "App"].forEach {
            XCTAssertFalse(ReleaseDetector.isDMG(fileName: $0), $0)
        }
    }

    func testFiltersDraftAndPrerelease() {
        let releases = [releaseDTO(id: 1, tag: "v1"), releaseDTO(id: 2, tag: "v2-beta", prerelease: true), releaseDTO(id: 3, tag: "draft", draft: true)]
        XCTAssertEqual(ReleaseDetector.eligibleReleases(from: releases, includePrerelease: false).map(\.id), [1])
        XCTAssertEqual(ReleaseDetector.eligibleReleases(from: releases, includePrerelease: true).map(\.id), [2, 1])
    }

    func testSortsByPublishedDate() {
        let old = releaseDTO(id: 1, tag: "v1", publishedAt: Date(timeIntervalSince1970: 100))
        let new = releaseDTO(id: 2, tag: "v2", publishedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ReleaseDetector.eligibleReleases(from: [old, new], includePrerelease: false).first?.id, 2)
    }

    func testDetectsByReleaseIDNotOnlyTag() {
        let current = Release(id: 1, repositoryID: 10, tagName: "v1", htmlURL: "https://github.com/a/b/releases/v1", publishedAt: Date(timeIntervalSince1970: 100))
        let candidate = releaseDTO(id: 2, tag: "v1", publishedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ReleaseDetector.detectChange(candidate: candidate, current: current), .newRelease)
    }

    func testTagAndPublishedDateChangesAreDetected() {
        let current = Release(id: 1, repositoryID: 10, tagName: "v1", htmlURL: "https://github.com/a/b/releases/v1", publishedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(ReleaseDetector.detectChange(candidate: releaseDTO(id: 1, tag: "v1.1", publishedAt: Date(timeIntervalSince1970: 100)), current: current), .newRelease)
        XCTAssertEqual(ReleaseDetector.detectChange(candidate: releaseDTO(id: 1, tag: "v1", publishedAt: Date(timeIntervalSince1970: 200)), current: current), .newRelease)
    }

    func testPrereleasePromotionIsDetected() {
        let current = Release(id: 1, repositoryID: 10, tagName: "v1", htmlURL: "https://github.com/a/b/releases/v1", isPrerelease: true)
        XCTAssertEqual(ReleaseDetector.detectChange(candidate: releaseDTO(id: 1, tag: "v1"), current: current), .promotedFromPrerelease)
    }

    func testNotesOrAssetChangesAreNotNewRelease() {
        let current = Release(id: 1, repositoryID: 10, tagName: "v1", htmlURL: "https://github.com/a/b/releases/v1", publishedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        let candidate = releaseDTO(id: 1, tag: "v1", publishedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 300), assetIDs: [99])
        XCTAssertEqual(ReleaseDetector.detectChange(candidate: candidate, current: current), .none)
        XCTAssertTrue(ReleaseDetector.assetsChanged(from: [], to: candidate.assets))
    }

    func testEmptyReleaseList() {
        XCTAssertTrue(ReleaseDetector.eligibleReleases(from: [], includePrerelease: false).isEmpty)
    }
}

func releaseDTO(
    id: Int64,
    tag: String,
    publishedAt: Date? = Date(timeIntervalSince1970: 100),
    updatedAt: Date? = Date(timeIntervalSince1970: 100),
    draft: Bool = false,
    prerelease: Bool = false,
    assetIDs: [Int64] = []
) -> GitHubReleaseDTO {
    GitHubReleaseDTO(
        id: id,
        tagName: tag,
        name: tag,
        body: "Notes",
        htmlURL: "https://github.com/a/b/releases/tag/\(tag)",
        publishedAt: publishedAt,
        createdAt: publishedAt,
        updatedAt: updatedAt,
        isDraft: draft,
        isPrerelease: prerelease,
        assets: assetIDs.map {
            GitHubAssetDTO(id: $0, name: "App-\($0).dmg", size: 100, contentType: "application/octet-stream", browserDownloadURL: "https://github.com/a/b/App.dmg", createdAt: nil, updatedAt: nil, downloadCount: 0)
        }
    )
}
