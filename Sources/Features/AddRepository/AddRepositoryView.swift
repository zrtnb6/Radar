import SwiftUI

struct AddRepositoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var duplicateRepository: Repository?
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("添加 GitHub 项目").font(AppTypography.pageTitle)
                    Text("粘贴仓库或 Release 页面链接，自动识别 Owner 和 Repository。")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("GitHub URL").font(AppTypography.itemTitle)
                TextField("https://github.com/owner/repository", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($isURLFieldFocused)
                    .disabled(isAdding)
                    .onSubmit { addRepository() }
                    .accessibilityIdentifier("add-repository-url")
                Text("支持仓库首页、/releases 和 /releases/tag/version 链接。公开仓库无需 Token。")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if isAdding {
                HStack(spacing: AppSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("正在获取仓库信息和 Release…")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let duplicateRepository {
                Label("已添加 \(duplicateRepository.fullName)，可直接打开已有项目。", systemImage: "checkmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.dmg)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isAdding)
                if duplicateRepository != nil {
                    Button("打开已有项目") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("添加项目") { addRepository() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                        .accessibilityIdentifier("add-repository-submit")
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 540, height: 310)
        .onAppear { isURLFieldFocused = true }
    }

    private func addRepository() {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        duplicateRepository = nil
        Task {
            do {
                let outcome = try await appState.addRepository(urlString)
                switch outcome {
                case .added:
                    dismiss()
                case .duplicate(let repository):
                    duplicateRepository = repository
                }
            } catch {
                errorMessage = error.userFacingMessage
            }
            isAdding = false
        }
    }
}
