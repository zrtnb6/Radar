import Foundation
import SwiftUI
import SwiftData
import AppKit

private enum RepositorySortOrder: String, CaseIterable, Identifiable {
    case releaseDate
    case name
    case addedAt

    var id: String { rawValue }
    var title: String {
        switch self {
        case .releaseDate: return "Release 发布时间"
        case .name: return "项目名称"
        case .addedAt: return "添加时间"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Repository.addedAt, order: .reverse) private var repositories: [Repository]
    @Query(sort: \Release.publishedAt, order: .reverse) private var releases: [Release]
    @Query private var assets: [Asset]
    @AppStorage("repositorySortOrder") private var sortOrder = RepositorySortOrder.releaseDate.rawValue
    @AppStorage(AppSettings.onlyDMG) private var onlyDMG = false
    @State private var searchText = ""
    @State private var pendingDelete: Repository?
    @State private var showingDeleteConfirmation = false
    @State private var showingDownloads = false

    private var selectedRepository: Repository? {
        repositories.first { $0.id == appState.selectedRepositoryID }
    }

    private var visibleRepositories: [Repository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = repositories.filter { repository in
            if onlyDMG {
                guard let latest = latestRelease(for: repository), !assets(for: latest).filter(\.isDMG).isEmpty else { return false }
            }
            if query.isEmpty { return true }
            return repository.fullName.localizedCaseInsensitiveContains(query) ||
                repository.displayDescription.localizedCaseInsensitiveContains(query)
        }

        let order = RepositorySortOrder(rawValue: sortOrder) ?? .releaseDate
        return filtered.sorted { lhs, rhs in
            switch order {
            case .name:
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            case .addedAt:
                return lhs.addedAt > rhs.addedAt
            case .releaseDate:
                return latestRelease(for: lhs)?.sortDate ?? .distantPast > latestRelease(for: rhs)?.sortDate ?? .distantPast
            }
        }
    }

    var body: some View {
        // 用系统 NavigationSplitView：侧栏是完整的一块，边栏开关由系统放在标题栏最左侧，
        // 与窗口红绿灯同一条水平线，收起前后布局不变。
        NavigationSplitView {
            repositoryList
                .navigationSplitViewColumnWidth(
                    min: AppLayout.sidebarMinimum,
                    ideal: AppLayout.sidebarIdeal,
                    max: AppLayout.sidebarMaximum
                )
        } detail: {
            detailContent
        }
        .frame(minWidth: 920, minHeight: 600)
        .navigationTitle("Radar")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { appState.showingAddRepository = true } label: {
                    Label("添加项目", systemImage: "plus")
                }
                .help("添加 GitHub 项目 (⌘N)")

                Button { Task { await appState.refreshSelected() } } label: {
                    if syncService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(syncService.isRefreshing)
                .help("检查当前项目；未选中时检查全部 (⌘R 检查全部)")

                Menu {
                    Picker("排序", selection: $sortOrder) {
                        ForEach(RepositorySortOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
                .help("排序方式")

                Button { showingDownloads.toggle() } label: {
                    Label {
                        HStack(spacing: 3) {
                            Text("下载")
                            if downloads.activeCount > 0 {
                                Text("\(downloads.activeCount)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                }
                .popover(isPresented: $showingDownloads, arrowEdge: .bottom) {
                    DownloadCenterView()
                        .environmentObject(downloads)
                }
                .help("查看 App 内下载任务")

                Button { openSettings() } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $appState.showingAddRepository) {
            AddRepositoryView()
                .environmentObject(appState)
        }
        .alert("删除这个项目？", isPresented: $showingDeleteConfirmation, presenting: pendingDelete) { repository in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                appState.deleteRepository(repository)
                pendingDelete = nil
            }
        } message: { repository in
            Text("将移除 \(repository.fullName) 的本地缓存和通知记录，不会影响 GitHub 仓库。")
        }
        .onAppear {
            if appState.selectedRepositoryID == nil {
                appState.selectedRepositoryID = visibleRepositories.first?.id
            }
            #if DEBUG
            if CommandLine.arguments.contains("--open-settings") ||
                UserDefaults.standard.bool(forKey: "DebugOpenSettings") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    openSettings()
                }
            }
            if DebugFixtures.autoDownloadDemoEnabled {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    if let asset = assets.first(where: { $0.isDMG }) {
                        appState.downloadManager.start(asset: asset)
                    }
                }
            }
            if UserDefaults.standard.bool(forKey: "DebugShowDownloadsPanel") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    showingDownloads = true
                }
            }
            #endif
        }
    }

    // MARK: - 侧栏

    private var repositoryList: some View {
        List(selection: $appState.selectedRepositoryID) {
            ForEach(visibleRepositories) { repository in
                RepositoryRow(
                    repository: repository,
                    latestRelease: latestRelease(for: repository),
                    dmgCount: dmgCount(for: latestRelease(for: repository)),
                    isSelected: repository.id == appState.selectedRepositoryID
                )
                .tag(repository.id)
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                .contextMenu { repositoryContextMenu(repository) }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索项目")
        .overlay {
            if repositories.isEmpty {
                emptyState
            } else if visibleRepositories.isEmpty {
                noResultsState
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let repository = selectedRepository {
            RepositoryDetailView(
                repository: repository,
                releases: releases(for: repository),
                assets: assets.filter { asset in releases(for: repository).contains { $0.id == asset.releaseID } }
            )
        } else {
            EmptyStateView(
                systemImage: "shippingbox",
                title: "选择一个项目",
                message: "在左侧选择仓库以查看 Release Notes、DMG 附件和版本历史。"
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        EmptyStateView(
            systemImage: "dot.radiowaves.up.forward",
            title: "开始监控 Release",
            message: "添加你关心的 GitHub 仓库，Radar 会识别正式版本和 DMG 附件。",
            actionTitle: "添加 GitHub 项目"
        ) { appState.showingAddRepository = true }
    }

    @ViewBuilder
    private var noResultsState: some View {
        ContentUnavailableView("没有匹配的项目", systemImage: "magnifyingglass", description: Text("调整搜索内容或筛选条件。"))
    }

    @ViewBuilder
    private func repositoryContextMenu(_ repository: Repository) -> some View {
        Button { Task { await syncService.refresh(repositoryIDs: [repository.id]) } } label: {
            Label("立即检查", systemImage: "arrow.clockwise")
        }
        Button {
            if let url = URL.safeHTTPS(repository.url) { NSWorkspace.shared.open(url) }
        } label: {
            Label("打开 GitHub 页面", systemImage: "safari")
        }
        Divider()
        Button {
            repository.isIgnored.toggle()
            try? modelContext.save()
        } label: {
            Label(repository.isIgnored ? "恢复监控" : "忽略项目", systemImage: repository.isIgnored ? "play" : "pause")
        }
        Button(role: .destructive) {
            pendingDelete = repository
            showingDeleteConfirmation = true
        } label: {
            Label("删除项目", systemImage: "trash")
        }
    }

    private func latestRelease(for repository: Repository) -> Release? {
        guard let id = repository.latestReleaseID else { return nil }
        return releases.first { $0.id == id && $0.repositoryID == repository.id }
    }

    private func releases(for repository: Repository) -> [Release] {
        releases.filter { $0.repositoryID == repository.id && !$0.isDraft }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private func assets(for release: Release) -> [Asset] {
        assets.filter { $0.releaseID == release.id }
    }

    private func dmgCount(for release: Release?) -> Int {
        guard let release else { return 0 }
        return assets.filter { $0.releaseID == release.id && $0.isDMG }.count
    }
}
