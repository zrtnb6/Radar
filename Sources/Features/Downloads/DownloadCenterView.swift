import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("下载").font(AppTypography.itemTitle)
                Spacer()
                if !downloads.orderedItems.isEmpty {
                    Button("清除记录") { downloads.clearFinished() }
                        .buttonStyle(.borderless)
                        .font(AppTypography.caption)
                }
            }
            Text("保存到 \((downloads.downloadsDirectoryURL.path as NSString).abbreviatingWithTildeInPath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Divider()

            if downloads.orderedItems.isEmpty {
                VStack(spacing: AppSpacing.xs) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("暂无下载任务").font(AppTypography.secondary)
                    Text("在项目详情里点击附件旁的「下载」即可开始。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(downloads.orderedItems) { item in
                    DownloadCenterRow(item: item)
                    if item.id != downloads.orderedItems.last?.id { Divider() }
                }
            }
        }
        .padding(AppLayout.contentPadding)
        .frame(width: 380)
    }
}

private struct DownloadCenterRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: item.state == .completed ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(item.state == .completed ? AppColors.dmg : .secondary)
                    .frame(width: 16)
                Text(item.assetName)
                    .font(AppTypography.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if item.state == .completed {
                    Button {
                        downloads.reveal(id: item.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                    .accessibilityLabel("在 Finder 中显示")
                }
                statusLabel
            }

            switch item.state {
            case .downloading:
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(Int(item.progress * 100))% · \(item.progressSummary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("取消") { downloads.cancel(id: item.id) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            case .completed:
                EmptyView()
            case .failed:
                HStack {
                    Text(item.errorMessage ?? "下载失败")
                        .font(.caption2)
                        .foregroundStyle(AppColors.error)
                        .lineLimit(1)
                    Spacer()
                    Button("清除") { downloads.remove(id: item.id) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            case .cancelled:
                HStack {
                    Text("已取消").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("清除") { downloads.remove(id: item.id) }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.state {
        case .downloading:
            Text("下载中").font(.caption2).foregroundStyle(.secondary)
        case .completed:
            StatusPill(text: "已完成", color: AppColors.dmg)
        case .failed:
            Text("失败").font(.caption2).foregroundStyle(AppColors.error)
        case .cancelled:
            Text("已取消").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
