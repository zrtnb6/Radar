import SwiftUI

struct RepositoryRow: View {
    let repository: Repository
    let latestRelease: Release?
    let dmgCount: Int
    var isSelected = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            RepositoryAvatar(urlString: repository.avatarURL, isSelected: isSelected)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(repository.name)
                        .font(AppTypography.itemTitle)
                        .lineLimit(1)
                    if repository.isIgnored {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("已忽略，自动检查已暂停")
                    }
                    if let latestRelease, !latestRelease.isRead {
                        Circle()
                            .fill(isSelected ? Color.white : AppColors.newRelease)
                            .frame(width: 7, height: 7)
                            .help("有新版本")
                    }
                    Spacer(minLength: 0)
                    if let latestRelease {
                        Text(latestRelease.tagName)
                            .font(AppTypography.tag)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(repository.displayDescription)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Group {
                    if let latestRelease {
                        HStack(spacing: AppSpacing.xs) {
                            Label("发布 \(AppFormatters.relativeDate(latestRelease.publishedAt))", systemImage: "arrow.up.circle")
                                .help("发布时间：\(AppFormatters.releaseDate(latestRelease.publishedAt))")
                            Spacer(minLength: AppSpacing.xs)
                            if dmgCount > 0 {
                                Label("\(dmgCount) DMG", systemImage: "externaldrive")
                                    .foregroundStyle(AppColors.dmg)
                                    .help("\(dmgCount) 个 DMG 附件")
                            } else {
                                Text("无 DMG").foregroundStyle(.tertiary)
                            }
                        }
                        HStack(spacing: AppSpacing.xs) {
                            Label("编辑 \(AppFormatters.relativeDate(latestRelease.updatedAt))", systemImage: "pencil")
                                .help("编辑时间：\(AppFormatters.releaseDate(latestRelease.updatedAt))")
                            Spacer(minLength: AppSpacing.xs)
                            Label("检查 \(AppFormatters.relativeDate(repository.lastCheckedAt))", systemImage: "checkmark.circle")
                                .help("最近检查：\(AppFormatters.releaseDate(repository.lastCheckedAt))")
                        }
                    } else {
                        HStack(spacing: AppSpacing.xs) {
                            if repository.lastError != nil {
                                Label("检查失败", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(AppColors.warning)
                            } else {
                                Text("暂无 Release").foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Label("检查 \(AppFormatters.relativeDate(repository.lastCheckedAt))", systemImage: "checkmark.circle")
                                .help("最近检查：\(AppFormatters.releaseDate(repository.lastCheckedAt))")
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: AppLayout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
