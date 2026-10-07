import HostCore
import Testing

@Suite("What the menubar says")
struct MenuTextTests {
    @Test(arguments: [(0, "No Remote connected"), (1, "1 Remote connected"), (2, "2 Remotes connected")])
    func countsConnectedRemotes(_ count: Int, _ text: String) {
        #expect(MenuText.remotes(count) == text)
    }

    @Test func showsTheRemotesAddressReadyToCopy() {
        #expect(MenuText.serve(.serving(url: "https://mac.example.ts.net", funnel: false), port: 8484) == [
            MenuLine("Remote at https://mac.example.ts.net",
                     copy: .init(label: "Copy Remote Address", text: "https://mac.example.ts.net")),
        ])
    }

    /// Until Pairing exists, anyone who reaches the Remote can drive the Mac.
    @Test func warnsThatFunnelOpensTheRemoteToTheInternet() {
        let lines = MenuText.serve(.serving(url: "https://mac.example.ts.net", funnel: true), port: 8484)
        #expect(lines.dropFirst() == [
            MenuLine("Funnel is on: anyone on the internet can reach the Remote",
                     copy: .init(label: "Copy Command: tailscale serve reset && tailscale serve --bg 8484",
                                 text: "tailscale serve reset && tailscale serve --bg 8484")),
        ])
    }

    @Test func saysWhyItCannotTellWhetherServeReachesTheHost() {
        #expect(MenuText.serve(.unknown("Tailscale CLI not found"), port: 8484) == [
            MenuLine("Can't check tailscale serve: Tailscale CLI not found"),
        ])
    }

    @Test func offersTheServeCommandForTheHostsPortWhenServeMissesIt() {
        #expect(MenuText.serve(.notServing, port: 9000) == [
            MenuLine("tailscale serve doesn't reach the Host",
                     copy: .init(label: "Copy Command: tailscale serve --bg 9000", text: "tailscale serve --bg 9000")),
        ])
    }
}
