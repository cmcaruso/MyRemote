import CoreGraphics
import Foundation
import HostCore

/// The Dock's private calls the Dock Gestures need, resolved at run time so a missing symbol only turns
/// that part off (docs/adr/0001).
@MainActor
enum Dock {
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let applicationServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
    private static let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)

    private static let sendNotification = symbol(applicationServices, "CoreDockSendNotification", as: SendNotification.self)
    private static let mainConnection = symbol(coreGraphics, "CGSMainConnectionID", as: MainConnection.self)
    private static let activeSpace = symbol(coreGraphics, "CGSGetActiveSpace", as: ActiveSpace.self)
    private static let copyDisplaySpaces = symbol(coreGraphics, "CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Tells the Dock to show Mission Control, App Exposé, the desktop or Apps, as its own key commands do.
    /// Each one toggles.
    static func send(_ action: DockAction) {
        let name = switch action {
        case .missionControl: "com.apple.expose.awake"
        case .appExpose: "com.apple.expose.front.awake"
        case .showDesktop: "com.apple.showdesktop.awake"
        case .apps: "com.apple.launchpad.toggle"
        case .spaceLeft, .spaceRight: ""
        }
        guard !name.isEmpty, let sendNotification else { return }
        _ = sendNotification(name as CFString, 0)
    }

    /// How many Spaces the display with the active Space has; 2 if it can't tell.
    static func spaceCount() -> Int {
        guard let mainConnection, let activeSpace, let copyDisplaySpaces,
              let displays = copyDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return 2 }
        let active = activeSpace(mainConnection())
        let spaces = displays.lazy.compactMap { $0["Spaces"] as? [[String: Any]] }
            .first { $0.contains { ($0["ManagedSpaceID"] as? UInt64) == active } }
        return spaces?.count ?? 2
    }
}
