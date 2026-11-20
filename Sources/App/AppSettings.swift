import Foundation

enum AppSettings {
    static let launchAtLogin = "launchAtLogin"
    static let automaticChecks = "automaticChecks"
    static let checkInterval = "checkInterval"
    static let ignoreArchived = "ignoreArchived"
    static let monitorPrerelease = "monitorPrerelease"
    static let onlyDMG = "onlyDMG"
    static let notificationsEnabled = "notificationsEnabled"
    static let newReleaseNotifications = "newReleaseNotifications"
    static let assetChangeNotifications = "assetChangeNotifications"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            launchAtLogin: false,
            automaticChecks: true,
            checkInterval: 6.0,
            ignoreArchived: true,
            monitorPrerelease: false,
            onlyDMG: false,
            notificationsEnabled: true,
            newReleaseNotifications: true,
            assetChangeNotifications: false
        ])
    }
}
