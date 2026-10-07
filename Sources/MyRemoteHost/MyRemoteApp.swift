import AppKit
import HostCore
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
        // Verbatim: a localized Text would group the port's digits ("8.484").
        Text(verbatim: host.serving ? "Serving on 127.0.0.1:\(host.port)" : "Not serving: \(host.serverError ?? "starting…")")
        if let serve = host.serve {
            ForEach(MenuText.serve(serve, port: host.port), id: \.text) { line in
                Text(line.text)
                if let copy = line.copy {
                    Button(copy.label) { host.copy(copy.text) }
                }
            }
        } else {
            Text("Checking tailscale serve…")
        }
        Text(MenuText.remotes(host.remotes))
        Divider()
        if host.accessibilityGranted {
            Text("Accessibility: granted")
        } else {
            Text("Accessibility: not granted, the Remote can't move the pointer")
            Button("Open Accessibility Settings…") { host.openAccessibilitySettings() }
        }
        Divider()
        if LoginItem.available {
            Toggle("Launch at Login", isOn: Binding(
                get: { host.loginItem == .enabled },
                set: { host.setLaunchAtLogin($0) }))
            if host.loginItem == .requiresApproval {
                Text("Launch at login is waiting for your approval")
                Button("Open Login Items Settings…") { LoginItem.openSettings() }
            }
            if let error = host.loginItemError {
                Text("Launch at login: \(error)")
            }
        } else {
            Text("Launch at login works only in the built app")
        }
        Divider()
        Button("Quit MyRemote") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
