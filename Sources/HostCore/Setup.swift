import Foundation

/// The first-run guide: the steps from a fresh Mac to a paired Remote, and which are done, read from
/// what the Host can check. It opens on first launch and from the menu until every step is done.
public struct Setup: Equatable, Sendable {
    public enum Step: String, CaseIterable, Sendable {
        case installTailscale, logIn, https, serve, accessibility, iPhoneTailscale, pair
    }

    public enum State: Equatable, Sendable {
        case done
        /// The next thing to do.
        case todo
        /// Waits on an earlier step.
        case waiting
    }

    /// Whether the Tailscale app or CLI is on the Mac.
    public var tailscaleInstalled: Bool
    /// Nil while unknown: not installed, not answering, or not checked yet.
    public var tailscale: TailscaleStatus?
    public var serve: ServeCheck?
    public var accessibilityGranted: Bool
    public var pairedRemotes: Int

    public init(tailscaleInstalled: Bool, tailscale: TailscaleStatus?, serve: ServeCheck?,
                accessibilityGranted: Bool, pairedRemotes: Int) {
        self.tailscaleInstalled = tailscaleInstalled
        self.tailscale = tailscale
        self.serve = serve
        self.accessibilityGranted = accessibilityGranted
        self.pairedRemotes = pairedRemotes
    }

    public func state(of step: Step) -> State {
        // A paired Remote proves the whole path works, even if a check can't tell right now.
        if pairedRemotes > 0, step != .accessibility { return .done }
        let running = tailscale?.state == .running
        switch step {
        case .installTailscale:
            return tailscaleInstalled ? .done : .todo
        case .logIn:
            guard tailscaleInstalled else { return .waiting }
            return running ? .done : .todo
        case .https:
            guard running, let tailscale else { return .waiting }
            return tailscale.magicDNS && tailscale.httpsCertificates ? .done : .todo
        case .serve:
            if case .serving = serve { return .done }
            return state(of: .https) == .done ? .todo : .waiting
        case .accessibility:
            return accessibilityGranted ? .done : .todo
        case .iPhoneTailscale:
            guard running else { return .waiting }
            return tailscale?.hasIOSPeer == true ? .done : .todo
        case .pair:
            return state(of: .serve) == .done ? .todo : .waiting
        }
    }

    public var complete: Bool { Step.allCases.allSatisfy { state(of: $0) == .done } }

    /// The step to point at: the first one not done that isn't waiting on another.
    public var current: Step? { Step.allCases.first { state(of: $0) == .todo } }

    /// The Remote's address once serve reaches the Host.
    public var remoteURL: String? {
        if case let .serving(url, _) = serve { return url }
        return nil
    }

    /// Arguments for the Tailscale CLI that proxy the tailnet's HTTPS to the Host. It takes port 443,
    /// for an address without a port, unless something else already serves there. Nil when every port
    /// Tailscale allows for HTTPS is taken.
    public static func serveArguments(port: Int, httpsPortsInUse: Set<Int>) -> [String]? {
        guard let https = [443, 8443, 10000].first(where: { !httpsPortsInUse.contains($0) }) else { return nil }
        return https == 443 ? ["serve", "--bg", "\(port)"] : ["serve", "--bg", "--https=\(https)", "\(port)"]
    }
}
