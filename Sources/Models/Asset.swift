import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: Int64
    var releaseID: Int64
    var name: String
    var size: Int64
    var contentType: String
    var downloadURL: String
    var createdAt: Date?
    var updatedAt: Date?
    var downloadCount: Int?
    var isDMG: Bool

    init(
        id: Int64,
        releaseID: Int64,
        name: String,
        size: Int64,
        contentType: String,
        downloadURL: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        downloadCount: Int? = nil,
        isDMG: Bool
    ) {
        self.id = id
        self.releaseID = releaseID
        self.name = name
        self.size = size
        self.contentType = contentType
        self.downloadURL = downloadURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.downloadCount = downloadCount
        self.isDMG = isDMG
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
