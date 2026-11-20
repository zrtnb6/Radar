import SwiftUI
import AppKit

struct RepositoryDetailView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.monitorPrerelease) private var includePrerelease = false
    let repository: Repository
    let releases: [Release]
    let assets: [Asset]
    @State private var selectedHistoryRelease: Release?
    @State private var isNotesExpanded = false

    private var latestRelease: Release? {
        releases.first { $0.id == repository.latestReleaseID }
    }

    private var visibleHistory: [Release] {
        releases.filter { includePrerelease || !$0.isPrerelease }.prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                repositoryHeader
                if let lastError = repository.lastError {
                    errorBanner(lastError)
                }
                latestReleaseSection
                historySection
            }
            .padding(AppLayout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.markRead(repository)
            openPendingReleaseIfNeeded()
            #if DEBUG
            // 仅供视觉验收：以启动参数或调试开关直接展开，便于截取展开态。
            if CommandLine.arguments.contains("--ui-notes-expanded") ||
                UserDefaults.standard.bool(forKey: "DebugNotesExpanded") {
                isNotesExpanded = true
            }
            #endif
        }
        .onChange(of: repository.id) { _, _ in
            selectedHistoryRelease = nil
            isNotesExpanded = false
            appState.markRead(repository)
        }
        .onChange(of: appState.pendingReleaseID) { _, _ in
            openPendingReleaseIfNeeded()
        }
        .sheet(item: $selectedHistoryRelease) { release in
            ReleaseHistoryDetailView(release: release, assets: assets(for: release))
                .environmentObject(appState.downloadManager)
                .frame(minWidth: 580, idealWidth: 680, minHeight: 480, idealHeight: 620)
        }
    }

    private var repositoryHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                RepositoryAvatar(urlString: repository.avatarURL, size: AppLayout.detailIconSize)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(repository.name).font(AppTypography.pageTitle)
                        if repository.isArchived { StatusPill(text: "已归档", color: AppColors.warning, systemImage: "archivebox") }
                        if repository.isIgnored { StatusPill(text: "已忽略", systemImage: "pause") }
                    }
                    Text(repository.fullName)
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    if let url = URL.safeHTTPS(repository.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Label("GitHub 页面", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
            Text(repository.displayDescription)
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.lg) {
                Label(AppFormatters.compactCount(repository.stars), systemImage: "star")
                    .help("Star 数量")
                if let language = repository.language, !language.isEmpty {
                    Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Label("检查于 \(AppFormatters.relativeDate(repository.lastCheckedAt))", systemImage: "clock")
            }
            .font(AppTypography.caption)
            .foregroundStyle(.secondary)
        }
        .appCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("本次检查失败").font(AppTypography.itemTitle)
                Text(message).font(AppTypography.caption)
                Text("以下展示最近一次成功同步的缓存数据。").font(.caption2)
            }
            Spacer()
        }
        .foregroundStyle(AppColors.warning)
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    @ViewBuilder
    private var latestReleaseSection: some View {
        if let release = latestRelease {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    SectionHeader(title: "最新 Release", systemImage: "tag")
                    Spacer()
                    Button {
                        if let url = URL.safeHTTPS(release.htmlURL) { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("在 GitHub 查看", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
                }

                HStack(spacing: AppSpacing.xs) {
                    Text(release.displayTitle).font(.title3.weight(.semibold))
                    StatusPill(text: release.tagName, color: .accentColor)
                    if release.isPrerelease { StatusPill(text: "预发布", color: AppColors.warning) }
                }

                Grid(alignment: .leading, horizontalSpacing: AppSpacing.md, verticalSpacing: AppSpacing.xs) {
                    KeyValueRow(key: "发布时间", value: AppFormatters.releaseDate(release.publishedAt))
                    KeyValueRow(key: "编辑时间", value: AppFormatters.releaseDate(release.updatedAt))
                    KeyValueRow(key: "检查时间", value: AppFormatters.releaseDate(repository.lastCheckedAt))
                }
                .font(AppTypography.caption)

                Divider()
                notesDisclosure(release.body)

                dmgSection(for: release)
                otherAssetsSection(for: release)
            }
            .appCard()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionHeader(title: "最新 Release", systemImage: "tag")
                ContentUnavailableView {
                    Label("暂无 Release", systemImage: "tray")
                } description: {
                    Text("该仓库目前没有符合监控策略的正式 Release。项目仍会保留并继续检查。")
                }
                .frame(minHeight: 180)
            }
            .appCard()
        }
    }

    private func notesDisclosure(_ body: String?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isNotesExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    // 16pt 占位与卡片内系统 Label 图标宽度一致，保证标题文字左边缘对齐。
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isNotesExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                    Text("Release Notes").font(AppTypography.itemTitle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("release-notes-toggle")
            .help(isNotesExpanded ? "收起 Release Notes" : "展开 Release Notes")

            if isNotesExpanded {
                releaseNotes(body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func releaseNotes(_ body: String?) -> some View {
        let notes = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if notes.isEmpty {
            Text("此版本没有 Release Notes。")
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
        } else {
            ReleaseNotesView(markdown: notes)
        }
    }

    private func dmgSection(for release: Release) -> some View {
        let dmgAssets = assets(for: release).filter(\.isDMG)
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Divider()
            HStack {
                Label("DMG 下载附件", systemImage: "externaldrive")
                    .font(AppTypography.itemTitle)
                Spacer()
                if !dmgAssets.isEmpty { StatusPill(text: "\(dmgAssets.count) 个", color: AppColors.dmg) }
            }
            if dmgAssets.isEmpty {
                Label("此 Release 没有 DMG 附件，其他附件仍可查看。", systemImage: "info.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dmgAssets.enumerated()), id: \.element.id) { index, asset in
                        AssetRow(asset: asset)
                        if index < dmgAssets.count - 1 { Divider().padding(.leading, 32) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func otherAssetsSection(for release: Release) -> some View {
        let otherAssets = assets(for: release).filter { !$0.isDMG }
        if !otherAssets.isEmpty {
            DisclosureGroup("其他附件（\(otherAssets.count)）") {
                VStack(spacing: 0) {
                    ForEach(otherAssets) { asset in
                        AssetRow(asset: asset)
                    }
                }
                .padding(.top, AppSpacing.xs)
            }
            .font(AppTypography.caption)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                SectionHeader(title: "Release 历史", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("最近 \(visibleHistory.count) 个")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            if visibleHistory.isEmpty {
                Text("暂无版本历史").font(AppTypography.secondary).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleHistory.enumerated()), id: \.element.id) { index, release in
                        Button {
                            selectedHistoryRelease = release
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "tag").foregroundStyle(.secondary).frame(width: 20)
                                Text(release.tagName).font(AppTypography.tag).frame(minWidth: 84, alignment: .leading)
                                Text(release.displayTitle).font(AppTypography.secondary).lineLimit(1)
                                Spacer()
                                let count = assets(for: release).filter(\.isDMG).count
                                if count > 0 {
                                    Label("\(count)", systemImage: "externaldrive")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.dmg)
                                }
                                Text(AppFormatters.relativeDate(release.publishedAt))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 88, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < visibleHistory.count - 1 { Divider().padding(.leading, 32) }
                    }
                }
            }
        }
        .appCard()
    }

    private func assets(for release: Release) -> [Asset] {
        assets.filter { $0.releaseID == release.id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func openPendingReleaseIfNeeded() {
        guard let pendingID = appState.pendingReleaseID else { return }
        if pendingID != repository.latestReleaseID, let release = releases.first(where: { $0.id == pendingID }) {
            selectedHistoryRelease = release
        }
        appState.pendingReleaseID = nil
    }
}

private struct AssetRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    let asset: Asset

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: asset.isDMG ? "externaldrive.fill" : "doc")
                .foregroundStyle(asset.isDMG ? AppColors.dmg : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(AppTypography.secondary).lineLimit(1).truncationMode(.middle)
                Text("\(asset.formattedSize) · \(asset.contentType)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            downloadControls
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var downloadControls: some View {
        if let item = downloads.items[asset.id] {
            switch item.state {
            case .downloading:
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 108)
                    HStack(spacing: AppSpacing.xs) {
                        Text("\(Int(item.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("取消") { downloads.cancel(id: asset.id) }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                }
            case .completed:
                HStack(spacing: AppSpacing.xs) {
                    StatusPill(text: "已下载", color: AppColors.dmg, systemImage: "checkmark.circle")
                    Button {
                        downloads.reveal(id: asset.id)
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
                }
            case .failed:
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.errorMessage ?? "下载失败")
                        .font(.caption2)
                        .foregroundStyle(AppColors.error)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("重试") { downloads.retry(asset: asset) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            case .cancelled:
                Button("重新下载") { downloads.retry(asset: asset) }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
            }
        } else {
            Button {
                downloads.start(asset: asset)
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("在 App 内下载到「下载」文件夹，不跳转浏览器，也不会自动打开或安装")
        }
    }
}

private struct ReleaseHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let release: Release
    let assets: [Asset]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(release.displayTitle).font(AppTypography.pageTitle)
                    Text("\(release.tagName) · 发布于 \(AppFormatters.releaseDate(release.publishedAt))")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding(AppLayout.contentPadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if let body = release.body, !body.isEmpty {
                        ReleaseNotesView(markdown: body)
                    } else {
                        Text("此版本没有 Release Notes。").foregroundStyle(.secondary)
                    }
                    if !assets.isEmpty {
                        Divider()
                        Text("附件").font(AppTypography.sectionTitle)
                        ForEach(assets) { AssetRow(asset: $0) }
                    }
                }
                .padding(AppLayout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
