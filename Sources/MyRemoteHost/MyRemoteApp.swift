import AppKit
import SwiftUI

@main
struct MyRemoteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("MyRemote", systemImage: "hand.point.up.left") {
            HostMenu(host: delegate.host)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let host = Host()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run unbundled with `swift run` (the bundle sets LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        host.start()
    }
}

struct HostMenu: View {
    let host: Host

    var body: some View {
        Text(host.serving ? "Serving on 127.0.0.1:\(host.port)" : "Not serving: \(host.serverError ?? "starting…")")
        Text(host.remotes == 1 ? "1 Remote connected" : "\(host.remotes) Remotes connected")
        Divider()
        if host.accessibilityGranted {
            Text("Accessibility: granted")
        } else {
            Text("Accessibility: not granted, the Remote can't move the pointer")
            Button("Open Accessibility Settings…") { host.openAccessibilitySettings() }
        }
        Divider()
        Button("Quit MyRemote") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
