import Foundation

@MainActor
final class SyncScheduler: ObservableObject {
    private let syncService: SyncService
    private var timerTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?

    init(syncService: SyncService) {
        self.syncService = syncService
    }

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.checkIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await self?.checkIfNeeded()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkIfNeeded() }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
    }

    func checkIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: AppSettings.automaticChecks), !syncService.isRefreshing else { return }
        if let retryAt = syncService.rateLimitNotBefore, retryAt > .now { return }

        let repositories = (try? syncService.fetchRepositories()) ?? []
        let monitored = repositories.filter { repository in
            !repository.isIgnored && !(UserDefaults.standard.bool(forKey: AppSettings.ignoreArchived) && repository.isArchived)
        }
        guard !monitored.isEmpty else { return }

        let interval = max(1, UserDefaults.standard.double(forKey: AppSettings.checkInterval)) * 3600
        let needsCheck = monitored.contains { repository in
            guard let lastCheckedAt = repository.lastCheckedAt else { return true }
            return Date().timeIntervalSince(lastCheckedAt) >= interval
        }
        if needsCheck {
            await syncService.refresh()
        }
    }
}
