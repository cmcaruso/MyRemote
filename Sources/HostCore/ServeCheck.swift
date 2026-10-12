import Foundation

/// Whether `tailscale serve` proxies the tailnet's HTTPS to the Host, read from `tailscale serve status --json`.
public enum ServeCheck: Equatable, Sendable {
    /// The Remote is at `url`. With Funnel on, that address is open to the whole internet, not just the tailnet.
    case serving(url: String, funnel: Bool)
    /// Nothing serve proxies reaches the Host's port.
    case notServing
    /// The Host can't tell, and why (no Tailscale CLI, Tailscale not running…).
    case unknown(String)

    public init(statusJSON: Data, port: Int) {
        let status: Status?
        do {
            status = try JSONDecoder().decode(Status?.self, from: statusJSON)
        } catch {
            self = .unknown("unexpected output from the Tailscale CLI")
            return
        }
        for (hostPort, site) in status?.Web ?? [:] {
            guard let proxy = site.Handlers?["/"]?.Proxy.flatMap(URL.init(string:)),
                  proxy.scheme == "http", ["127.0.0.1", "localhost"].contains(proxy.host()), proxy.port == port
            else { continue }
            let url = "https://" + (hostPort.hasSuffix(":443") ? String(hostPort.dropLast(4)) : hostPort)
            self = .serving(url: url, funnel: status?.AllowFunnel?[hostPort] == true)
            return
        }
        self = .notServing
    }

    /// The ports `tailscale serve` already listens on, which Setup mustn't take over.
    public static func portsInUse(statusJSON: Data) -> Set<Int> {
        let status = (try? JSONDecoder().decode(Status?.self, from: statusJSON)) ?? nil
        return Set((status?.TCP ?? [:]).keys.compactMap { Int($0) })
    }
}

/// The parts of Tailscale's `ipn.ServeConfig` the check reads.
private struct Status: Decodable {
    struct Site: Decodable { var Handlers: [String: Handler]? }
    struct Handler: Decodable { var Proxy: String? }
    struct Listener: Decodable {}
    var TCP: [String: Listener]?
    var Web: [String: Site]?
    var AllowFunnel: [String: Bool]?
}
