import AppKit
import Foundation
import SwiftData
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRepositoryID: Int64?
    @Published var pendingReleaseID: Int64?
    @Published var showingAddRepository = false
    @Published var unreadCount = 0
    @Published var storageError: String?

    let container: ModelContainer
    let syncService: SyncService
    let scheduler: SyncScheduler
    let notificationService: NotificationService
    let downloadManager: DownloadManager
    private var notificationTask: Task<Void, Never>?

    init(container suppliedContainer: ModelContainer? = nil, storageError: String? = nil) {
        AppSettings.registerDefaults()
        #if DEBUG
        if DebugFixtures.downloadDemoEnabled { DebugFixtures.prepareDemoDownloadsDirectory() }
        self.downloadManager = DownloadManager(
            configuration: DebugFixtures.downloadSessionConfiguration() ?? .default,
            downloadsDirectory: DebugFixtures.demoDownloadsDirectoryIfEnabled
        )
        #else
        self.downloadManager = DownloadManager()
        #endif
        let resolvedContainer: ModelContainer
        let resolvedError: String?
        if let suppliedContainer {
            resolvedContainer = suppliedContainer
            resolvedError = storageError
        } else {
            #if DEBUG
            if DebugFixtures.isEnabled {
                let fixturePersistence = PersistenceController(inMemory: true)
                resolvedContainer = fixturePersistence.container
                resolvedError = nil
                DebugFixtures.populate(context: fixturePersistence.container.mainContext)
            } else {
                let persistence = PersistenceController.shared
                resolvedContainer = persistence.container
                resolvedError = persistence.storageError
            }
            #else
            let persistence = PersistenceController.shared
            resolvedContainer = persistence.container
            resolvedError = persistence.storageError
            #endif
        }
        self.container = resolvedContainer
        self.storageError = resolvedError

        // 真实启动（非测试注入容器）时预置默认项目；DEBUG 夹具场景跳过，
        // 避免调试用的 UserDefaults 标记污染正式安装。
        if suppliedContainer == nil {
            #if DEBUG
            if !DebugFixtures.isEnabled {
                DefaultRepository.seedIfNeeded(context: resolvedContainer.mainContext)
            }
            #else
            DefaultRepository.seedIfNeeded(context: resolvedContainer.mainContext)
            #endif
        }

        let notificationService = NotificationService()
        self.notificationService = notificationService
        let syncService = SyncService(modelContext: resolvedContainer.mainContext, notifications: notificationService)
        self.syncService = syncService
        scheduler = SyncScheduler(syncService: syncService)
        updateUnreadCount()
        observeNotificationClicks()
        scheduler.start()
    }

    func refreshAll() async {
        await syncService.refresh()
        updateUnreadCount()
    }

    func refreshSelected() async {
        if let selectedRepositoryID {
            await syncService.refresh(repositoryIDs: [selectedRepositoryID])
        } else {
            await syncService.refresh()
        }
        updateUnreadCount()
    }

    func addRepository(_ url: String) async throws -> AddRepositoryOutcome {
        let outcome = try await syncService.addRepository(urlString: url)
        switch outcome {
        case .added(let repository), .duplicate(let repository):
            selectedRepositoryID = repository.id
        }
        updateUnreadCount()
        return outcome
    }

    func deleteRepository(_ repository: Repository) {
        do {
            let deletedID = repository.id
            try syncService.delete(repository)
            if selectedRepositoryID == deletedID { selectedRepositoryID = nil }
            updateUnreadCount()
        } catch {
            syncService.lastSyncError = "删除项目失败：\(error.localizedDescription)"
        }
    }

    func markRead(_ repository: Repository) {
        syncService.markRepositoryRead(repository)
        updateUnreadCount()
    }

    func updateUnreadCount() {
        let descriptor = FetchDescriptor<Release>(predicate: #Predicate { !$0.isRead && !$0.isDraft })
        unreadCount = (try? container.mainContext.fetchCount(descriptor)) ?? 0
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let hasVisibleMainWindow = NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
        if !hasVisibleMainWindow {
            NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
        }
    }

    private func observeNotificationClicks() {
        notificationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: NotificationService.openReleaseNotification)
            for await notification in notifications {
                guard let self,
                      let repositoryString = notification.userInfo?["repositoryID"] as? String,
                      let repositoryID = Int64(repositoryString),
                      let releaseString = notification.userInfo?["releaseID"] as? String,
                      let releaseID = Int64(releaseString) else { continue }
                self.selectedRepositoryID = repositoryID
                self.pendingReleaseID = releaseID
                self.activateMainWindow()
            }
        }
    }
}
