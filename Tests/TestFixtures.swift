import Foundation

enum TestFixtures {
    static func repositoryJSON(id: Int64 = 42, owner: String = "octo", name: String = "Sample", archived: Bool = false) -> String {
        """
        {
          "id": \(id), "name": "\(name)", "full_name": "\(owner)/\(name)",
          "owner": {"login": "\(owner)", "avatar_url": "https://avatars.githubusercontent.com/u/1"},
          "description": "Native release monitoring fixture", "html_url": "https://github.com/\(owner)/\(name)",
          "homepage": "https://example.com", "stargazers_count": 1234, "forks_count": 56,
          "language": "Swift", "topics": ["macos", "swiftui"],
          "created_at": "2024-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
          "pushed_at": "2026-01-02T00:00:00Z", "archived": \(archived)
        }
        """
    }

    static func releaseJSON(
        id: Int64 = 100,
        tag: String = "v1.0.0",
        body: String = "Initial release",
        publishedAt: String = "2026-01-02T12:00:00Z",
        updatedAt: String = "2026-01-02T12:00:00Z",
        prerelease: Bool = false,
        draft: Bool = false,
        assets: String = ""
    ) -> String {
        """
        {
          "id": \(id), "tag_name": "\(tag)", "name": "Release \(tag)", "body": "\(body)",
          "html_url": "https://github.com/octo/Sample/releases/tag/\(tag)",
          "published_at": "\(publishedAt)", "created_at": "\(publishedAt)", "updated_at": "\(updatedAt)",
          "draft": \(draft), "prerelease": \(prerelease), "assets": [\(assets)]
        }
        """
    }

    static func assetJSON(id: Int64, name: String, contentType: String = "application/octet-stream") -> String {
        """
        {"id": \(id), "name": "\(name)", "size": 10485760, "content_type": "\(contentType)",
         "browser_download_url": "https://github.com/octo/Sample/releases/download/v1/\(name)",
         "created_at": "2026-01-02T12:00:00Z", "updated_at": "2026-01-02T12:00:00Z", "download_count": 8}
        """
    }

    static func standardHandler(repositoryID: Int64 = 42, name: String = "Sample", releases: @escaping () -> String) -> MockURLProtocol.Handler {
        { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path.hasSuffix("/releases") {
                return (mockResponse(url: url), Data(releases().utf8))
            }
            return (mockResponse(url: url), Data(repositoryJSON(id: repositoryID, name: name).utf8))
        }
    }
}
