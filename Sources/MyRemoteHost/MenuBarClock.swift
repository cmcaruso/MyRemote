import AppKit
import ApplicationServices

/// The menu-bar clock, which opens and closes Notification Center when pressed. There's no gesture event
/// for Notification Center, so the Host presses the clock through Accessibility.
@MainActor
enum MenuBarClock {
    /// Presses the clock, Control Center's `com.apple.menuextra.clock` item; nothing if it can't be found.
    static func press() {
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        // Don't hold up the Host's input if Control Center is busy.
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar: AXUIElement = attribute(app, "AXExtrasMenuBar"),
              let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute),
              let clock = items.first(where: { attribute($0, kAXIdentifierAttribute) == "com.apple.menuextra.clock" }) else { return }
        AXUIElementPerformAction(clock, kAXPressAction as CFString)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
