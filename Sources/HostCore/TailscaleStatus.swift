import Foundation

/// What Setup needs from `tailscale status --json`: whether the Mac is on a tailnet, whether the tailnet
/// can give it an HTTPS address, and whether an iPhone has joined.
public struct TailscaleStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        /// Logged out, or the tailnet's admin hasn't approved the Mac yet.
        case needsLogin
        /// Turned off in the Tailscale app, or still starting.
        case stopped
    }

    public var state: State
    /// The Mac's MagicDNS name without the trailing dot, as `tailscale serve` uses it.
    public var dnsName: String?
    public var magicDNS: Bool
    /// HTTPS Certificates are on in the admin console when the tailnet hands out cert domains.
    public var httpsCertificates: Bool
    /// Whether any other device on the tailnet is an iPhone or iPad.
    public var hasIOSPeer: Bool

    public init(state: State, dnsName: String? = nil, magicDNS: Bool = false,
                httpsCertificates: Bool = false, hasIOSPeer: Bool = false) {
        self.state = state
        self.dnsName = dnsName
        self.magicDNS = magicDNS
        self.httpsCertificates = httpsCertificates
        self.hasIOSPeer = hasIOSPeer
    }

    /// Nil when the output isn't `tailscale status --json`.
    public init?(statusJSON: Data) {
        guard let status = try? JSONDecoder().decode(Status.self, from: statusJSON) else { return nil }
        state = switch status.BackendState {
        case "Running": .running
        case "NeedsLogin", "NeedsMachineAuth": .needsLogin
        default: .stopped
        }
        let name = status.Self_?.DNSName ?? ""
        dnsName = name.isEmpty ? nil : (name.hasSuffix(".") ? String(name.dropLast()) : name)
        magicDNS = status.CurrentTailnet?.MagicDNSEnabled ?? false
        httpsCertificates = !(status.CertDomains ?? []).isEmpty
        hasIOSPeer = (status.Peer ?? [:]).values.contains { $0.OS == "iOS" }
    }
}

/// The parts of Tailscale's `ipnstate.Status` Setup reads.
private struct Status: Decodable {
    struct Node: Decodable {
        var DNSName: String?
        var OS: String?
    }
    struct Tailnet: Decodable { var MagicDNSEnabled: Bool? }

    var BackendState: String?
    var Self_: Node?
    var Peer: [String: Node]?
    var CurrentTailnet: Tailnet?
    var CertDomains: [String]?

    enum CodingKeys: String, CodingKey {
        case BackendState, Peer, CurrentTailnet, CertDomains
        case Self_ = "Self"
    }
}
