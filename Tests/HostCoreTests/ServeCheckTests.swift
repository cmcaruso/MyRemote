import Foundation
import HostCore
import Testing

@Suite("Whether tailscale serve reaches the Host")
struct ServeCheckTests {
    /// `tailscale serve status --json` after `tailscale serve --bg 8484`, with a made-up machine name.
    private let servingPort8484 = """
        {
          "TCP": { "443": { "HTTPS": true } },
          "Web": {
            "mac.example.ts.net:443": {
              "Handlers": { "/": { "Proxy": "http://127.0.0.1:8484" } }
            }
          }
        }
        """

    private func check(_ json: String, port: Int = 8484) -> ServeCheck {
        ServeCheck(statusJSON: Data(json.utf8), port: port)
    }

    @Test func servesTheRemoteAtTheMachinesHTTPSAddress() {
        #expect(check(servingPort8484) == .serving(url: "https://mac.example.ts.net", funnel: false))
    }

    @Test func doesNotReachAHostOnAnotherPort() {
        #expect(check(servingPort8484, port: 9000) == .notServing)
    }

    /// `tailscale serve --bg --https 8443 8484`
    @Test func includesAnHTTPSPortOtherThan443() {
        let json = servingPort8484.replacingOccurrences(of: "ts.net:443", with: "ts.net:8443")
        #expect(check(json) == .serving(url: "https://mac.example.ts.net:8443", funnel: false))
    }

    /// `tailscale funnel --bg 8484` serves the same config and opens it to the internet.
    @Test func noticesFunnelOpeningTheRemoteToTheInternet() {
        let json = servingPort8484.replacingOccurrences(
            of: "\"TCP\"", with: "\"AllowFunnel\": { \"mac.example.ts.net:443\": true }, \"TCP\"")
        #expect(check(json) == .serving(url: "https://mac.example.ts.net", funnel: true))
    }

    private func proxying(_ target: String, path: String = "/") -> String {
        servingPort8484.replacingOccurrences(of: "\"/\": { \"Proxy\": \"http://127.0.0.1:8484\" }",
                                             with: "\"\(path)\": { \"Proxy\": \"\(target)\" }")
    }

    /// The Host binds to loopback only, so a proxy to the same port on another address misses it.
    @Test(arguments: [
        ("http://localhost:8484", true),
        ("http://127.0.0.1:8484", true),
        ("http://192.168.1.20:8484", false),
        ("https+insecure://127.0.0.1:8484", false),
    ])
    func reachesTheHostOnlyThroughLoopback(_ target: String, _ reaches: Bool) {
        #expect((check(proxying(target)) != .notServing) == reaches)
    }

    /// The Remote asks for `/ws` and its files at the root, so it can't live under a path.
    @Test func doesNotReachTheHostMountedUnderAPath() {
        #expect(check(proxying("http://127.0.0.1:8484", path: "/remote")) == .notServing)
    }

    /// With no serve config at all, the CLI prints the nil config as `null`.
    @Test(arguments: ["{}", "null\n"])
    func doesNotReachTheHostWhenNothingIsServed(_ json: String) {
        #expect(check(json) == .notServing)
    }

    @Test func cannotTellFromOutputThatIsNotAServeConfig() {
        guard case .unknown = check("Tailscale is stopped.") else {
            Issue.record("expected .unknown")
            return
        }
    }
}
