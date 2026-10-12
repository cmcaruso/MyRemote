import Foundation
import HostCore
import Testing

@Suite("Reading tailscale status for Setup")
struct TailscaleStatusTests {
    /// `tailscale status --json`, trimmed to what Setup reads, with made-up names.
    private let running = """
        {
          "BackendState": "Running",
          "Self": { "DNSName": "mac.example.ts.net.", "OS": "macOS" },
          "Peer": {
            "nodekey:1": { "DNSName": "iphone.example.ts.net.", "OS": "iOS" },
            "nodekey:2": { "DNSName": "nas.example.ts.net.", "OS": "linux" }
          },
          "CurrentTailnet": { "Name": "me@example.com", "MagicDNSEnabled": true },
          "CertDomains": ["mac.example.ts.net"]
        }
        """

    private func status(_ json: String) -> TailscaleStatus? {
        TailscaleStatus(statusJSON: Data(json.utf8))
    }

    @Test func readsAMacReadyToServe() {
        #expect(status(running) == TailscaleStatus(state: .running, dnsName: "mac.example.ts.net",
                                                    magicDNS: true, httpsCertificates: true, hasIOSPeer: true))
    }

    @Test func noticesHTTPSCertificatesAreOff() {
        let json = running.replacingOccurrences(of: "\"CertDomains\": [\"mac.example.ts.net\"]", with: "\"CertDomains\": null")
        #expect(status(json)?.httpsCertificates == false)
    }

    @Test func noticesNoIPhoneHasJoined() {
        #expect(status(running.replacingOccurrences(of: "\"iOS\"", with: "\"android\""))?.hasIOSPeer == false)
    }

    @Test(arguments: [("NeedsLogin", TailscaleStatus.State.needsLogin), ("NeedsMachineAuth", .needsLogin),
                      ("Stopped", .stopped), ("Starting", .stopped)])
    func readsWhetherTheMacIsOnTheTailnet(_ backend: String, _ state: TailscaleStatus.State) {
        #expect(status(running.replacingOccurrences(of: "\"Running\"", with: "\"\(backend)\""))?.state == state)
    }

    @Test func refusesOutputThatIsNotStatus() {
        #expect(status("not json") == nil)
    }
}

@Suite("The first-run Setup")
struct SetupTests {
    private let ready = TailscaleStatus(state: .running, dnsName: "mac.example.ts.net",
                                        magicDNS: true, httpsCertificates: true, hasIOSPeer: true)

    private func setup(installed: Bool = true, tailscale: TailscaleStatus? = nil, serve: ServeCheck? = nil,
                       accessibility: Bool = false, paired: Int = 0) -> Setup {
        Setup(tailscaleInstalled: installed, tailscale: tailscale, serve: serve,
              accessibilityGranted: accessibility, pairedRemotes: paired)
    }

    @Test func startsWithInstallingTailscaleOnAFreshMac() {
        let fresh = setup(installed: false)
        #expect(fresh.current == .installTailscale)
        #expect(fresh.state(of: .logIn) == .waiting)
        #expect(fresh.state(of: .serve) == .waiting)
        #expect(fresh.state(of: .pair) == .waiting)
        // Accessibility doesn't depend on Tailscale.
        #expect(fresh.state(of: .accessibility) == .todo)
    }

    @Test func asksToLogInWhenTailscaleIsInstalledButNotConnected() {
        #expect(setup(tailscale: TailscaleStatus(state: .needsLogin)).current == .logIn)
        #expect(setup(tailscale: nil).current == .logIn)
    }

    @Test func asksForHTTPSCertificatesBeforeServe() {
        var tailnet = ready
        tailnet.httpsCertificates = false
        let s = setup(tailscale: tailnet, serve: .notServing)
        #expect(s.current == .https)
        #expect(s.state(of: .serve) == .waiting)
    }

    @Test func offersToTurnOnServeOnceTheTailnetCanGiveAnAddress() {
        let s = setup(tailscale: ready, serve: .notServing, accessibility: true)
        #expect(s.current == .serve)
        #expect(s.state(of: .pair) == .waiting)
    }

    @Test func pairsOnceTheRemoteHasAnAddress() {
        let s = setup(tailscale: ready, serve: .serving(url: "https://mac.example.ts.net", funnel: false), accessibility: true)
        #expect(s.current == .pair)
        #expect(s.remoteURL == "https://mac.example.ts.net")
        #expect(!s.complete)
    }

    @Test func isCompleteWithAPairedRemoteAndAccessibility() {
        #expect(setup(tailscale: ready, serve: .serving(url: "https://mac.example.ts.net", funnel: false),
                      accessibility: true, paired: 1).complete)
    }

    /// A paired Remote proves Tailscale and serve work even when the CLI can't be asked.
    @Test func trustsAPairedRemoteOverChecksThatCannotTell() {
        let s = setup(tailscale: nil, serve: .unknown("Tailscale CLI not found"), accessibility: false, paired: 1)
        #expect(s.state(of: .serve) == .done)
        #expect(s.current == .accessibility)
    }

    @Test func servesOn443WhenItIsFree() {
        #expect(Setup.serveArguments(port: 8484, httpsPortsInUse: []) == ["serve", "--bg", "8484"])
    }

    /// Something else on the tailnet's 443 keeps it; the Remote takes another port.
    @Test func leavesAnotherServiceOn443Alone() {
        #expect(Setup.serveArguments(port: 8484, httpsPortsInUse: [443])
            == ["serve", "--bg", "--https=8443", "8484"])
        #expect(Setup.serveArguments(port: 8484, httpsPortsInUse: [443, 8443])
            == ["serve", "--bg", "--https=10000", "8484"])
    }

    /// With every HTTPS port taken, Setup turns nothing on rather than replace another service.
    @Test func takesNoPortWhenAllAreServed() {
        #expect(Setup.serveArguments(port: 8484, httpsPortsInUse: [443, 8443, 10000]) == nil)
    }

    @Test func readsThePortsServeAlreadyUses() {
        let json = #"{ "TCP": { "443": { "HTTPS": true }, "8443": { "HTTPS": true } } }"#
        #expect(ServeCheck.portsInUse(statusJSON: Data(json.utf8)) == [443, 8443])
        #expect(ServeCheck.portsInUse(statusJSON: Data("{}".utf8)).isEmpty)
    }
}
