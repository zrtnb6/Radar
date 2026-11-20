import SwiftUI
import SwiftData
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Release.publishedAt, order: .reverse) private var releases: [Release]
    @Query private var repositories: [Repository]

    private var recentReleases: [Release] {
        Array(releases.filter { !$0.isDraft }.prefix(5))
    }

    var body: some View {
        Button("打开 Radar") { openMainWindow() }
            .keyboardShortcut("o", modifiers: [.command])

        Menu("最近更新") {
            if recentReleases.isEmpty {
                Text("暂无 Release")
            } else {
                ForEach(recentReleases) { release in
                    Button(menuTitle(for: release)) {
                        appState.selectedRepositoryID = release.repositoryID
                        appState.pendingReleaseID = release.id
                        openMainWindow()
                    }
                }
            }
        }

        if downloads.activeCount > 0 {
            Text("正在下载 \(downloads.activeCount) 项")
        }

        Divider()
        Button(syncService.isRefreshing ? "正在检查…" : "立即检查") {
            Task { await appState.refreshAll() }
        }
        .disabled(syncService.isRefreshing)
        .keyboardShortcut("r", modifiers: [.command])

        Button("添加项目…") {
            appState.showingAddRepository = true
            openMainWindow()
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("设置…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()
        Button("退出 Radar") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: [.command])
            .onAppear { appState.updateUnreadCount() }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func menuTitle(for release: Release) -> String {
        let repositoryName = repositories.first { $0.id == release.repositoryID }?.name ?? "项目"
        let unread = release.isRead ? "" : " ●"
        return "\(repositoryName) — \(release.tagName)\(unread)"
    }
}
