import Foundation

enum ReleaseChange: Equatable {
    case none
    case newRelease
    case promotedFromPrerelease
}

enum ReleaseDetector {
    static func isDMG(fileName: String) -> Bool {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).pathExtension.caseInsensitiveCompare("dmg") == .orderedSame
    }

    static func eligibleReleases(from releases: [GitHubReleaseDTO], includePrerelease: Bool) -> [GitHubReleaseDTO] {
        releases
            .filter { !$0.isDraft && (includePrerelease || !$0.isPrerelease) }
            .sorted { lhs, rhs in
                let left = lhs.publishedAt ?? lhs.createdAt ?? .distantPast
                let right = rhs.publishedAt ?? rhs.createdAt ?? .distantPast
                if left == right { return lhs.id > rhs.id }
                return left > right
            }
    }

    static func detectChange(candidate: GitHubReleaseDTO, current: Release?) -> ReleaseChange {
        guard let current else { return .newRelease }
        if candidate.id != current.id { return .newRelease }
        if current.isPrerelease && !candidate.isPrerelease { return .promotedFromPrerelease }
        if candidate.tagName != current.tagName { return .newRelease }
        if let candidateDate = candidate.publishedAt, let currentDate = current.publishedAt,
           candidateDate > currentDate {
            return .newRelease
        }
        if candidate.publishedAt != nil && current.publishedAt == nil { return .newRelease }
        return .none
    }

    static func assetsChanged(from oldIDs: Set<Int64>, to newAssets: [GitHubAssetDTO]) -> Bool {
        oldIDs != Set(newAssets.map(\.id))
    }
}
