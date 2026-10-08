import Foundation
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

    /// The Host refuses Funnel traffic (it has no tailnet login), but the Remote's page is still public.
    @Test func warnsThatFunnelOpensTheRemoteToTheInternet() {
        let lines = MenuText.serve(.serving(url: "https://mac.example.ts.net", funnel: true), port: 8484)
        #expect(lines.dropFirst() == [
            MenuLine("Funnel is on: the Remote's address is public on the internet",
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

    private let rome = TimeZone(identifier: "Europe/Rome")!
    /// 8 Oct 2026, 14:00 in Rome.
    private let now = Date(timeIntervalSince1970: 1_791_460_800)

    private func row(paired: TimeInterval, lastUsed: TimeInterval) -> String {
        MenuText.pairedRemote(name: "iPhone", pairedAt: now - paired, lastSeen: now - lastUsed, now: now, timeZone: rome)
    }

    @Test func describesAPairedRemoteByWhenItPairedAndWasLastUsed() {
        #expect(row(paired: 3 * 86400, lastUsed: 120) == "iPhone · paired 5 Oct · last used 2 min ago")
    }

    @Test(arguments: [
        (20, "just now"),
        (59 * 60, "59 min ago"),
        (2 * 3600 + 59 * 60, "2 h ago"),
        (23 * 3600, "23 h ago"),
        (3 * 86400, "5 Oct"),
    ] as [(TimeInterval, String)])
    func saysHowLongAgoARemoteWasLastUsed(ago: TimeInterval, text: String) {
        #expect(row(paired: 10 * 86400, lastUsed: ago) == "iPhone · paired 28 Sep · last used \(text)")
    }

    @Test func listsNoPairedRemotes() {
        #expect(MenuText.pairedRemotes(0) == "No paired Remotes")
        #expect(MenuText.pairedRemotes(1) == "Paired Remotes (1)")
        #expect(MenuText.pairedRemotes(3) == "Paired Remotes (3)")
    }

    @Test(arguments: [(120, "2:00"), (61.4, "1:02"), (9, "0:09"), (0, "0:00"), (-5, "0:00")] as [(TimeInterval, String)])
    func countsDownTheLiveCode(left: TimeInterval, text: String) {
        #expect(MenuText.countdown(until: now + left, now: now) == text)
    }
}
