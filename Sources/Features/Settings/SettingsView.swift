import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.automaticChecks) private var automaticChecks = true
    @AppStorage(AppSettings.checkInterval) private var checkInterval = 6.0
    @AppStorage(AppSettings.ignoreArchived) private var ignoreArchived = true
    @AppStorage(AppSettings.monitorPrerelease) private var monitorPrerelease = false
    @AppStorage(AppSettings.onlyDMG) private var onlyDMG = false
    @AppStorage(AppSettings.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(AppSettings.newReleaseNotifications) private var newReleaseNotifications = true
    @AppStorage(AppSettings.assetChangeNotifications) private var assetChangeNotifications = false
    @AppStorage(AppSettings.launchAtLogin) private var launchAtLogin = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机启动", isOn: launchAtLoginBinding)
                Toggle("自动检查更新", isOn: $automaticChecks)
                Picker("检查间隔", selection: $checkInterval) {
                    Text("每 6 小时").tag(6.0)
                    Text("每 12 小时").tag(12.0)
                    Text("每 24 小时").tag(24.0)
                }
                .disabled(!automaticChecks)
            }

            Section {
                GitHubTokenSection(errorMessage: $errorMessage)
            } header: {
                Text("GitHub 令牌")
            } footer: {
                Text("未配置令牌时同一 IP 每小时仅 60 次请求；配置后按令牌计最高 5000 次/小时。公开仓库可不填；令牌仅提升 API 限额，访问私有仓库仍需对应的仓库权限。")
                    .font(AppTypography.caption)
            }

            Section("监控") {
                Toggle("忽略已归档仓库", isOn: $ignoreArchived)
                Toggle("监控 Prerelease", isOn: $monitorPrerelease)
                Toggle("只显示包含 DMG 的项目", isOn: $onlyDMG)
                Text("Draft 永远不会显示；没有 DMG 的 Release 默认仍会正常展示。")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通知") {
                Toggle("系统通知", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await appState.notificationService.requestAuthorizationIfNeeded() }
                        }
                    }
                Toggle("新 Release 通知", isOn: $newReleaseNotifications)
                    .disabled(!notificationsEnabled)
                Toggle("附件变化通知", isOn: $assetChangeNotifications)
                    .disabled(!notificationsEnabled)
                Text("首次添加项目只建立基线，不发送历史版本通知；同一 Release 不会重复提醒。")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"))")
                LabeledContent("项目地址", value: "本地 Xcode 工程")
                LabeledContent("系统要求", value: "macOS 14.0 或更高版本")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 760)
        .background(SettingsWindowButtonHider())
        .navigationTitle("Radar 设置")
        .alert("设置错误", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = enabled
            } catch {
                errorMessage = "无法更新开机启动设置：\(error.localizedDescription)"
            }
        }
    }
}

/// 设置窗口只保留红色关闭按钮：最小化与缩放按钮对设置页没有意义，
/// 直接从标题栏隐藏，而不是禁用成灰色。
private struct SettingsWindowButtonHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HiderView { HiderView() }
    func updateNSView(_ nsView: HiderView, context: Context) { nsView.apply() }

    final class HiderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}
