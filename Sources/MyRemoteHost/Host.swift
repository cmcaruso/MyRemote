import AppKit
import CoreGraphics
import Foundation
import HostCore
import ServiceManagement

/// The Host's state as the menu shows it, and the one place commands cross onto the main actor.
@MainActor @Observable
final class Host {
    /// Loopback port `tailscale serve` proxies to. Per machine: `defaults write <bundle id> port <n>`.
    let port: Int
    private(set) var serving = false
    private(set) var serverError: String?
    private(set) var remotes = 0
    private(set) var accessibilityGranted = CGPreflightPostEventAccess()
    /// Whether `tailscale serve` reaches the Host; nil until the first check.
    private(set) var serve: ServeCheck?
    private(set) var loginItem = LoginItem.status
    private(set) var loginItemError: String?
    let pairings = PairingStore()
    /// Plays the Phone Mic into the output picked in the menu.
    let mic = Microphone()
    /// The time the menu's "last used" is counted from, refreshed with the status checks.
    private(set) var now = Date.now

    private let injector = Injector()
    private let volume = Volume()
    private let laser = LaserOverlay()
    private let clients = Clients()
    /// The last volume state pushed; CoreAudio reports one change several times.
    private var lastVolume: String?

    init() {
        let configured = UserDefaults.standard.integer(forKey: "port")
        port = configured > 0 ? configured : 8484
    }

    func start() {
        if !accessibilityGranted {
            _ = CGRequestPostEventAccess()
            watchAccessibility()
        }

        // Every command from every Remote goes through this stream to the main actor.
        let (commands, continuation) = AsyncStream.makeStream(of: Command.self)
        Task {
            for await command in commands {
                switch command {
                case let .setVolume(level): volume.set(level)
                case .laserStart, .laserMove, .laserEnd: laser.apply(command)
                default: injector.apply(command)
                }
            }
        }

        // Keep every Remote's volume slider in step with the Mac.
        volume.onChange = { [weak self] in self?.pushVolume() }

        let server = Server(
            remoteDirectory: Self.remoteDirectory(),
            port: port,
            commands: continuation,
            clients: clients,
            pairings: pairings,
            onRemote: { [weak self] delta in
                await MainActor.run {
                    guard let self else { return }
                    self.remotes += delta
                    if delta < 0 {
                        self.injector.remoteLeft()
                        self.laser.end()
                    } else { self.pushVolume(force: true) }
                    self.checkServe()
                }
            },
            mic: mic.feed,
            onMic: { [weak self] stream, rate in
                await MainActor.run { self?.mic.stream(stream, rate: rate) }
            }
        )
        Task {
            serving = true
            do {
                try await server.run()
            } catch {
                serverError = "\(error)"
            }
            serving = false
        }

        watchStatus()
    }

    /// Serve and the login item change outside the Host (Terminal, System Settings), so look again now and then.
    private func watchStatus() {
        Task {
            while true {
                checkServe()
                loginItem = LoginItem.status
                now = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func checkServe() {
        let port = port
        Task { serve = await Tailscale.checkServe(port: port) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItem = LoginItem.status
    }

    /// Revokes one paired Remote, or all of them when `id` is nil, and drops their live connections.
    func revoke(_ id: Pairing.Remote.ID?) {
        if let id { pairings.revoke(id) } else { pairings.revokeAll() }
        let clients = clients
        Task { await clients.unpair(id) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Sends the volume state to every Remote; `force` also repeats an unchanged state, for a new Remote.
    private func pushVolume(force: Bool = false) {
        let text = volume.current().encoded()
        guard force || text != lastVolume else { return }
        lastVolume = text
        let clients = clients
        Task { await clients.broadcast(text) }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Accessibility is granted in System Settings while the Host runs; notice it without a restart.
    private func watchAccessibility() {
        Task {
            while !accessibilityGranted {
                try? await Task.sleep(for: .seconds(2))
                accessibilityGranted = CGPreflightPostEventAccess()
            }
        }
    }

    /// The Remote's files: inside the app bundle, or `./remote` when run with `swift run` from the repo root.
    private static func remoteDirectory() -> String {
        if let bundled = Bundle.main.resourceURL?.appending(path: "remote"),
           FileManager.default.fileExists(atPath: bundled.path(percentEncoded: false)) {
            return bundled.path(percentEncoded: false)
        }
        return FileManager.default.currentDirectoryPath + "/remote"
    }
}
