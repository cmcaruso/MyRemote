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
    private(set) var accessibilityGranted = Host.canPostEvents()
    /// Whether `tailscale serve` reaches the Host; nil until the first check.
    private(set) var serve: ServeCheck?
    /// Setup's view of Tailscale; nil until Setup first checks.
    private(set) var tailscale: TailscaleStatus?
    private(set) var tailscaleInstalled = Tailscale.installed
    /// Setup's Turn On for serve: running, and what went wrong last time.
    private(set) var serveStarting = false
    private(set) var serveProblem: String?
    private(set) var loginItem = LoginItem.status
    private(set) var loginItemError: String?
    let pairings = PairingStore()
    /// Plays the Phone Mic into the output picked in the menu.
    let mic = Microphone()
    /// The time the menu's "last used" is counted from, refreshed with the status checks.
    private(set) var now = Date.now

    private let injector = Injector(followsFingers: MacTrackpad.followsFingers)
    private let volume = Volume()
    private let laser = LaserOverlay()
    private let macTrackpad = MacTrackpad()
    private let clients = Clients()
    /// The last volume state pushed; CoreAudio reports one change several times.
    private var lastVolume: String?
    /// The last Mac trackpad settings pushed; one change in System Settings signals several times.
    private var lastTrackpad: String?
    /// The connection that sent the last command, so it holds any drag, Gesture or Laser in progress.
    private var driver: UUID?

    init() {
        let configured = UserDefaults.standard.integer(forKey: "port")
        port = configured > 0 ? configured : 8484
    }

    /// Setup opens by itself until it has once seen every step done. A Host that already has a paired
    /// Remote predates Setup and skips it.
    static let setupFinishedKey = "setupFinished"
    var opensSetupAtLaunch: Bool {
        !UserDefaults.standard.bool(forKey: Self.setupFinishedKey) && pairings.remotes.isEmpty
    }

    var setup: Setup {
        Setup(tailscaleInstalled: tailscaleInstalled, tailscale: tailscale, serve: serve,
              accessibilityGranted: accessibilityGranted, pairedRemotes: pairings.remotes.count)
    }

    func start() {
        if !accessibilityGranted {
            // On first launch Setup asks for it in its turn, rather than macOS's prompt covering Setup.
            if !opensSetupAtLaunch { _ = CGRequestPostEventAccess() }
            watchAccessibility()
        }

        // Keep every Remote's volume slider in step with the Mac.
        volume.onChange = { [weak self] in self?.pushVolume() }
        // And their Gestures in step with the Mac's trackpad settings.
        macTrackpad.onChange = { [weak self] in self?.pushTrackpad() }

        let server = Server(
            remoteDirectory: Self.remoteDirectory(),
            port: port,
            onCommand: { [weak self] connection, command in
                await MainActor.run { self?.handle(command, from: connection) }
            },
            clients: clients,
            pairings: pairings,
            onRemote: { [weak self] connection, joined in
                await MainActor.run {
                    guard let self else { return }
                    self.remotes += joined ? 1 : -1
                    if !joined {
                        // Only the Remote that was driving let go; another one's drag or Laser carries on.
                        if self.driver == connection.id {
                            self.driver = nil
                            self.injector.remoteLeft()
                            self.laser.end()
                        }
                    } else {
                        self.pushVolume(force: true)
                        self.pushTrackpad(force: true)
                    }
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

    /// Every command from every Remote crosses onto the main actor here.
    private func handle(_ command: Command, from connection: Connection) {
        // A Remote revoked while this command was on its way doesn't get it run.
        guard pairings.isPaired(connection.remote) else { return }
        driver = connection.id
        switch command {
        case let .setVolume(level): volume.set(level)
        case .laserStart, .laserMove, .laserEnd: laser.apply(command)
        default: injector.apply(command)
        }
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

    /// Looks at everything Setup shows; Setup calls it every couple of seconds while it's open.
    func refreshSetup() async {
        accessibilityGranted = Self.canPostEvents()
        tailscaleInstalled = Tailscale.installed
        tailscale = await Tailscale.status()
        serve = await Tailscale.checkServe(port: port)
        if setup.complete { UserDefaults.standard.set(true, forKey: Self.setupFinishedKey) }
    }

    func turnOnServe() {
        serveStarting = true
        serveProblem = nil
        Task {
            switch await Tailscale.startServe(port: port) {
            case .started:
                break
            case let .needsApproval(link):
                serveProblem = "Your tailnet hasn't allowed Serve yet. Allow it on the page that opened, then click Turn On again."
                NSWorkspace.shared.open(link)
            case let .failed(reason):
                serveProblem = "Couldn't turn it on: \(reason). In Terminal, run tailscale serve --bg \(port)."
            }
            await refreshSetup()
            serveStarting = false
        }
    }

    /// Shows macOS's own prompt, which adds MyRemote to the Accessibility list, then the list itself.
    func requestAccessibility() {
        _ = CGRequestPostEventAccess()
        openAccessibilitySettings()
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

    /// Sends the Mac trackpad settings to every Remote, like `pushVolume`.
    private func pushTrackpad(force: Bool = false) {
        let text = macTrackpad.current().encoded()
        guard force || text != lastTrackpad else { return }
        lastTrackpad = text
        let clients = clients
        Task { await clients.broadcast(text) }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// CGPreflightPostEventAccess answers once per launch and keeps that answer, so a grant made while the
    /// Host runs never shows; AXIsProcessTrusted asks macOS again each time.
    private static func canPostEvents() -> Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    /// Accessibility is granted in System Settings while the Host runs; notice it without a restart.
    private func watchAccessibility() {
        Task {
            while !accessibilityGranted {
                try? await Task.sleep(for: .seconds(2))
                accessibilityGranted = Self.canPostEvents()
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
