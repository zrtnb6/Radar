import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let useDarkAppearance = environment["RELEASERADAR_UI_APPEARANCE"] == "dark" ||
            CommandLine.arguments.contains("--ui-dark") ||
            UserDefaults.standard.bool(forKey: "DebugDarkAppearance")
        let argumentSize = CommandLine.arguments.first(where: { $0.hasPrefix("--ui-window-size=") })?
            .split(separator: "=", maxSplits: 1).last.map(String.init)
        let requestedSize = environment["RELEASERADAR_UI_WINDOW_SIZE"] ??
            argumentSize ??
            UserDefaults.standard.string(forKey: "DebugWindowSize")

        if useDarkAppearance || requestedSize != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if useDarkAppearance {
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                    NSApp.windows.forEach { $0.appearance = NSAppearance(named: .darkAqua) }
                }
                if let requestedSize {
                    let parts = requestedSize.split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 {
                        NSApp.windows.first(where: { $0.canBecomeMain })?.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    }
                }
            }
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
