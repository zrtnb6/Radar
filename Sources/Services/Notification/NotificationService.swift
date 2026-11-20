import Foundation
import UserNotifications
import OSLog

protocol NotificationSending: AnyObject {
    func sendNewRelease(repository: Repository, release: Release) async -> Bool
    func sendAssetChange(repository: Repository, release: Release) async -> Bool
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationSending, @unchecked Sendable {
    static let openReleaseNotification = Notification.Name("ReleaseRadar.OpenRelease")
    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.releaseradar.macos", category: "Notifications")

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                return true
            case .notDetermined:
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            case .denied:
                return false
            @unknown default:
                return false
            }
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func sendNewRelease(repository: Repository, release: Release) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "Radar"
        content.subtitle = repository.fullName
        content.body = "\(repository.name) 发布了新版本 \(release.tagName)"
        content.sound = .default
        content.threadIdentifier = "releaseradar-new-releases"
        content.userInfo = ["repositoryID": String(repository.id), "releaseID": String(release.id)]
        return await deliver(content: content, identifier: "release-\(repository.id)-\(release.id)")
    }

    @discardableResult
    func sendAssetChange(repository: Repository, release: Release) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "Radar"
        content.subtitle = repository.fullName
        content.body = "\(release.tagName) 的附件列表已更新"
        content.sound = .default
        content.threadIdentifier = "releaseradar-asset-changes"
        content.userInfo = ["repositoryID": String(repository.id), "releaseID": String(release.id)]
        return await deliver(content: content, identifier: "assets-\(repository.id)-\(release.id)-\(UUID().uuidString)")
    }

    private func deliver(content: UNMutableNotificationContent, identifier: String) async -> Bool {
        guard UserDefaults.standard.bool(forKey: AppSettings.notificationsEnabled) else { return false }
        guard await requestAuthorizationIfNeeded() else { return false }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let repositoryID = userInfo["repositoryID"] as? String,
           let releaseID = userInfo["releaseID"] as? String {
            NotificationCenter.default.post(
                name: Self.openReleaseNotification,
                object: nil,
                userInfo: ["repositoryID": repositoryID, "releaseID": releaseID]
            )
        }
        completionHandler()
    }
}
