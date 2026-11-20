import XCTest

final class GitHubURLParserTests: XCTestCase {
    func testRepositoryURL() throws {
        let parsed = try GitHubURLParser.parse("https://github.com/apple/swift")
        XCTAssertEqual(parsed.owner, "apple")
        XCTAssertEqual(parsed.repository, "swift")
        XCTAssertEqual(parsed.fullName, "apple/swift")
        XCTAssertEqual(parsed.canonicalURL, "https://github.com/apple/swift")
    }

    func testSupportedURLVariants() throws {
        let urls = [
            "https://github.com/apple/swift/",
            "https://github.com/apple/swift/releases",
            "https://github.com/apple/swift/releases/tag/6.0.0",
            "https://www.github.com/apple/swift.git",
            " https://github.com/apple/swift/releases?tab=1 "
        ]
        for url in urls {
            let parsed = try GitHubURLParser.parse(url)
            XCTAssertEqual(parsed.fullName, "apple/swift", url)
        }
    }

    func testRejectsInvalidURLs() {
        let urls = [
            "",
            "github.com/apple/swift",
            "http://github.com/apple/swift",
            "https://gitlab.com/apple/swift",
            "https://github.com/apple",
            "https://github.com/apple/swift/issues/1",
            "https://user:secret@github.com/apple/swift",
            "https://github.com/apple/swift extra"
        ]
        for url in urls {
            XCTAssertThrowsError(try GitHubURLParser.parse(url), url) { error in
                XCTAssertEqual(error as? GitHubError, .invalidURL)
            }
        }
    }

    func testAllowsValidGitHubNames() throws {
        XCTAssertEqual(try GitHubURLParser.parse("https://github.com/a.b/c_d-e.f").fullName, "a.b/c_d-e.f")
    }
}
