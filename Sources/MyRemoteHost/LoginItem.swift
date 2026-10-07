import Foundation
import ServiceManagement

/// Launch at login, through the system's login items (System Settings → General → Login Items).
@MainActor
enum LoginItem {
    /// Only a built `.app` can be a login item, not the bare executable `swift run` starts.
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
