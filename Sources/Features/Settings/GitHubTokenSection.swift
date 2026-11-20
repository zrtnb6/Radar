import SwiftUI

/// 设置页「GitHub 令牌」区块内容。由 SettingsView 包在 Section 中，
/// 错误提示统一走外层 alert，避免多个 alert 叠加。
struct GitHubTokenSection: View {
    @Binding var errorMessage: String?

    @State private var tokenInput = ""
    @State private var hasToken = KeychainService.hasToken()
    @State private var isVerifying = false
    @State private var verification: VerificationResult?

    private enum VerificationResult {
        case success(GitHubRateLimitStatus)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            quotaComparison
            currentState

            SecureField("粘贴 GitHub Personal Access Token（github_pat_… 或 ghp_…）", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            actionRow

            if let verification {
                verificationView(verification)
            }

            securityNote
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private var quotaComparison: some View {
        HStack(spacing: AppSpacing.sm) {
            QuotaBadge(
                title: "未配置",
                quota: "60 次 / 小时",
                detail: "按来源 IP 计费",
                isActive: !hasToken,
                tint: AppColors.warning
            )
            QuotaBadge(
                title: "已配置令牌",
                quota: "5000 次 / 小时",
                detail: "按 Token 计费",
                isActive: hasToken,
                tint: AppColors.dmg
            )
        }
    }

    private var currentState: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: hasToken ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundStyle(hasToken ? AppColors.dmg : AppColors.warning)
            Text(hasToken
                 ? "已配置令牌：请求按认证配额计费；保存后立即生效，无需重启应用。"
                 : "当前未配置令牌：使用匿名配额，多个项目集中刷新时容易触发限流。")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Button(hasToken ? "更新令牌" : "保存令牌") { saveToken() }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if hasToken {
                Button("移除", role: .destructive) { removeToken() }
            }

            Button {
                Task { await verify() }
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    if isVerifying { ProgressView().controlSize(.small) }
                    Text(isVerifying ? "验证中…" : "验证令牌 / 查看配额")
                }
            }
            .disabled(isVerifying)

            Spacer()

            if let page = URL.safeHTTPS("https://github.com/settings/personal-access-tokens") {
                Link("在 GitHub 创建令牌", destination: page)
                    .font(AppTypography.caption)
            }
        }
    }

    private var securityNote: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("每个仓库每次检查约 2 次请求（仓库信息 + Release 列表）；10 个仓库一次全量刷新约占 20 次匿名配额。")
            Text("令牌仅保存在系统 Keychain，不写入数据库、日志、UserDefaults，也不会上传到第三方。公开仓库仍可在不配置令牌的情况下使用；访问私有仓库还需要令牌具备对应仓库的读取权限。")
        }
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func verificationView(_ result: VerificationResult) -> some View {
        switch result {
        case .success(let status):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: status.isAuthenticated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(status.isAuthenticated ? AppColors.dmg : AppColors.warning)
                    Text(status.isAuthenticated ? "令牌已生效" : "当前为匿名配额（未检测到令牌）")
                        .font(AppTypography.itemTitle)
                    Spacer()
                    StatusPill(
                        text: "\(status.limit) 次 / 小时",
                        color: status.isAuthenticated ? AppColors.dmg : AppColors.warning,
                        systemImage: "speedometer"
                    )
                }
                Text("剩余 \(status.remaining) 次 · 已用 \(status.used) 次 · 配额于 \(AppFormatters.releaseDate(status.reset)) 重置")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                if !status.isAuthenticated {
                    Text("请在上方粘贴令牌并保存后重新验证。")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        case .failure(let message):
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.error)
                Text("验证失败：\(message)")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.sm)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
    }

    @MainActor
    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            let status = try await GitHubClient().fetchRateLimit()
            verification = .success(status)
        } catch {
            verification = .failure(error.userFacingMessage)
        }
    }

    private func saveToken() {
        do {
            try KeychainService.saveToken(tokenInput)
            tokenInput = ""
            hasToken = KeychainService.hasToken()
            verification = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeToken() {
        do {
            try KeychainService.deleteToken()
            tokenInput = ""
            hasToken = false
            verification = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct QuotaBadge: View {
    let title: String
    let quota: String
    let detail: String
    let isActive: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? tint : Color.secondary)
                Text(title)
                    .font(AppTypography.tag)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
            Text(quota)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(isActive ? tint : Color.secondary)
            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(
            tint.opacity(isActive ? 0.10 : 0.04),
            in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(isActive ? tint.opacity(0.45) : AppColors.separator.opacity(0.40), lineWidth: 1)
        }
    }
}
