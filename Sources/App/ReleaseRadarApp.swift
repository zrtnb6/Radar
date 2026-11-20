import SwiftUI
import SwiftData

@main
struct RadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Radar", id: "main") {
            DashboardView()
                .environmentObject(appState)
                .environmentObject(appState.syncService)
                .environmentObject(appState.downloadManager)
                .frame(minWidth: 860, minHeight: 560)
        }
        .modelContainer(appState.container)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加 GitHub 项目…") { appState.showingAddRepository = true }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("立即检查") { Task { await appState.refreshAll() } }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.syncService)
        }
        .modelContainer(appState.container)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appState.syncService)
                .environmentObject(appState.downloadManager)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "dot.radiowaves.up.forward")
                if appState.unreadCount > 0 {
                    Text(String(appState.unreadCount))
                        .font(.caption2.monospacedDigit())
                }
            }
            .accessibilityLabel(appState.unreadCount > 0 ? "Radar，\(appState.unreadCount) 个待查看更新" : "Radar")
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(appState.container)
    }
}
