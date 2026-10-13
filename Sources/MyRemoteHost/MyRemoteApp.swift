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
        Window("Set Up MyRemote", id: SetupWindow.id) {
            SetupWindow(host: delegate.host)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(delegate.host.opensSetupAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        Window("Pair a Remote", id: PairWindow.id) {
            PairWindow(pairings: delegate.host.pairings)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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
    @Environment(\.openWindow) private var openWindow

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
        Button(host.setup.complete ? "Setup Guide…" : "Set Up MyRemote…") {
            openWindow(id: SetupWindow.id)
            NSApp.activate()
        }
        Button("Pair a Remote…") {
            host.pairings.newCode()
            openWindow(id: PairWindow.id)
            NSApp.activate()
        }
        pairedRemotes
        if let error = host.pairings.saveError {
            if host.pairings.unsavedRevocation {
                Text("Revocation not saved: \(error). It holds until MyRemote quits, and saving is tried again on every change.")
            } else {
                Text("Can't save paired Remotes: \(error)")
            }
        }
        Divider()
        phoneMic
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

    @ViewBuilder private var phoneMic: some View {
        let mic = host.mic
        ForEach(MenuText.phoneMic(live: mic.live, output: mic.output?.name,
                                  blackHoleInstalled: mic.blackHoleInstalled), id: \.text) { line in
            Text(line.text)
            if let copy = line.copy {
                Button(copy.label) { host.copy(copy.text) }
            }
        }
        if let error = mic.error {
            Text("Phone Mic: \(error)")
        }
        if !mic.outputs.isEmpty {
            Picker("Send Phone Mic To", selection: Binding(
                get: { mic.output?.id ?? "" },
                set: { mic.choose($0) })) {
                ForEach(mic.outputs) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var pairedRemotes: some View {
        let remotes = host.pairings.remotes
        if remotes.isEmpty {
            Text(MenuText.pairedRemotes(0))
        } else {
            Menu(MenuText.pairedRemotes(remotes.count)) {
                ForEach(remotes) { remote in
                    Menu(MenuText.pairedRemote(name: remote.name, pairedAt: remote.pairedAt,
                                               lastSeen: remote.lastSeen, now: host.now)) {
                        Button("Revoke") { host.revoke(remote.id) }
                    }
                }
                Divider()
                Button("Revoke All") { host.revoke(nil) }
            }
        }
    }
}

/// Shows the live Pairing code while a Remote types it, then confirms the Pairing and closes.
struct PairWindow: View {
    static let id = "pair"
    let pairings: PairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .frame(width: 300)
        .padding(24)
        .onDisappear { pairings.cancelCode() }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        if let name = pairings.justPaired {
            Label("Paired: \(name)", systemImage: "checkmark.circle.fill")
                .font(.title2)
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    dismiss()
                }
        } else if let code = pairings.code, now <= code.expires {
            VStack(spacing: 12) {
                Text("Type this code in the Remote")
                Text(code.digits.prefix(3) + " " + code.digits.suffix(3))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Text("Expires in \(MenuText.countdown(until: code.expires, now: now))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        } else {
            VStack(spacing: 12) {
                Text(pairings.codeDied ? "Too many wrong tries" : "The code expired").font(.title3)
                HStack {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("New Code") { pairings.newCode() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
