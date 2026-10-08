import Foundation
import HostCore
import Testing

@Suite("Pairing a Remote and checking its requests")
struct PairingTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let iPhone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"

    /// A request as `tailscale serve` forwards it from the owner's iPhone.
    private func request(cookie: String? = nil, login: String? = "owner@example.com",
                         origin: String? = "https://mac.example.ts.net", host: String? = "mac.example.ts.net") -> Pairing.Request {
        Pairing.Request(cookie: cookie, login: login, origin: origin, host: host, userAgent: iPhone)
    }

    /// Pairs a Remote and returns what its browser sends back as `Cookie` from then on.
    private func paired(_ pairing: inout Pairing, at now: Date? = nil) throws -> (Pairing.Remote, cookie: String) {
        let code = pairing.newCode(now: now ?? t0)
        guard case let .paired(remote, setCookie) = pairing.pair(request(), code: code.digits, now: now ?? t0) else {
            throw CancellationError()
        }
        return (remote, String(setCookie.prefix { $0 != ";" }))
    }

    @Test func aRemoteTypingTheLiveCodeIsPaired() throws {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)

        let result = pairing.pair(request(), code: code.digits, now: t0 + 30)

        guard case let .paired(remote, _) = result else { Issue.record("not paired: \(result)"); return }
        #expect(remote.name == "iPhone")
        #expect(pairing.remotes == [remote])
    }

    @Test func aWrongCodeIsRefused() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        let wrong = code.digits == "000000" ? "000001" : "000000"

        #expect(pairing.pair(request(), code: wrong, now: t0) == .refused(.wrongCode))
        #expect(pairing.remotes.isEmpty)
    }

    @Test func withoutALiveCodeNothingPairs() {
        var pairing = Pairing()
        #expect(pairing.pair(request(), code: "123456", now: t0) == .refused(.noCode))
    }

    @Test func aCodeExpiresAfterTwoMinutes() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        #expect(code.expires == t0 + 120)

        #expect(pairing.pair(request(), code: code.digits, now: t0 + 121) == .refused(.noCode))
    }

    @Test func aCodePairsOnlyOnce() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        _ = pairing.pair(request(), code: code.digits, now: t0)

        #expect(pairing.pair(request(), code: code.digits, now: t0) == .refused(.noCode))
        #expect(pairing.remotes.count == 1)
    }

    @Test func fiveWrongTriesKillTheCode() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        let wrong = code.digits == "000000" ? "000001" : "000000"
        for _ in 1...4 { #expect(pairing.pair(request(), code: wrong, now: t0) == .refused(.wrongCode)) }
        #expect(pairing.pair(request(), code: wrong, now: t0) == .refused(.tooManyTries))

        #expect(pairing.pair(request(), code: code.digits, now: t0) == .refused(.noCode))
        #expect(pairing.code == nil)
    }

    @Test func aCancelledCodeNoLongerPairs() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)

        pairing.cancelCode()

        #expect(pairing.code == nil)
        #expect(pairing.pair(request(), code: code.digits, now: t0) == .refused(.noCode))
    }

    @Test func aNewCodeReplacesTheLiveOne() {
        var pairing = Pairing()
        let first = pairing.newCode(now: t0)
        var second = pairing.newCode(now: t0)
        while second.digits == first.digits { second = pairing.newCode(now: t0) }

        #expect(pairing.pair(request(), code: first.digits, now: t0) == .refused(.wrongCode))
        guard case .paired = pairing.pair(request(), code: second.digits, now: t0) else { Issue.record("not paired"); return }
    }

    /// Funnel traffic, tagged devices and anything on the Mac that skips `tailscale serve` carry no login.
    @Test func pairingNeedsATailnetLogin() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)

        #expect(pairing.pair(request(login: nil), code: code.digits, now: t0) == .refused(.notOnTailnet))
        #expect(pairing.pair(request(login: ""), code: code.digits, now: t0) == .refused(.notOnTailnet))
    }

    @Test func pairingNeedsTheRemotesOwnOrigin() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)

        #expect(pairing.pair(request(origin: "https://evil.example"), code: code.digits, now: t0) == .refused(.otherOrigin))
        #expect(pairing.pair(request(origin: nil), code: code.digits, now: t0) == .refused(.otherOrigin))
        #expect(pairing.pair(request(origin: "http://mac.example.ts.net"), code: code.digits, now: t0) == .refused(.otherOrigin))
        #expect(pairing.pair(request(host: nil), code: code.digits, now: t0) == .refused(.otherOrigin))
    }

    @Test func aRefusedRequestDoesNotSpendATry() {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        for _ in 1...5 { _ = pairing.pair(request(origin: "https://evil.example"), code: "000000", now: t0) }

        guard case .paired = pairing.pair(request(), code: code.digits, now: t0) else { Issue.record("not paired"); return }
    }

    @Test func aPairedRemoteGetsIn() throws {
        var pairing = Pairing()
        let (remote, cookie) = try paired(&pairing)

        guard case let .paired(checked, _) = pairing.check(request(cookie: "theme=dark; " + cookie), now: t0 + 60) else {
            Issue.record("refused"); return
        }
        #expect(checked.id == remote.id)
    }

    @Test func theTokenCookieIsHiddenFromScriptsAndKeptForFourHundredDays() throws {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)
        guard case let .paired(_, setCookie) = pairing.pair(request(), code: code.digits, now: t0) else { Issue.record("not paired"); return }

        let attributes = Set(setCookie.split(separator: ";").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(attributes == ["HttpOnly", "Secure", "SameSite=Strict", "Path=/", "Max-Age=34560000"])
    }

    @Test func anUnpairedRemoteIsRefused() throws {
        var pairing = Pairing()
        let (_, cookie) = try paired(&pairing)
        let forged = cookie.prefix { $0 != "=" } + "=AAAA"

        #expect(pairing.check(request(cookie: nil), now: t0) == .refused(.notPaired))
        #expect(pairing.check(request(cookie: "theme=dark"), now: t0) == .refused(.notPaired))
        #expect(pairing.check(request(cookie: String(forged)), now: t0) == .refused(.notPaired))
    }

    @Test func aStolenCookieFailsUnderAnotherLogin() throws {
        var pairing = Pairing()
        let (_, cookie) = try paired(&pairing)

        #expect(pairing.check(request(cookie: cookie, login: "partner@example.com"), now: t0) == .refused(.otherLogin))
    }

    @Test func aPairedRemoteStillNeedsTheTailnetAndItsOrigin() throws {
        var pairing = Pairing()
        let (_, cookie) = try paired(&pairing)

        #expect(pairing.check(request(cookie: cookie, login: nil), now: t0) == .refused(.notOnTailnet))
        #expect(pairing.check(request(cookie: cookie, origin: "https://evil.example"), now: t0) == .refused(.otherOrigin))
    }

    @Test func aRevokedRemoteIsRefused() throws {
        var pairing = Pairing()
        let (phone, phoneCookie) = try paired(&pairing)
        let (tablet, tabletCookie) = try paired(&pairing)

        pairing.revoke(phone.id)

        #expect(pairing.check(request(cookie: phoneCookie), now: t0) == .refused(.notPaired))
        guard case .paired = pairing.check(request(cookie: tabletCookie), now: t0) else { Issue.record("refused"); return }
        #expect(pairing.remotes.map(\.id) == [tablet.id])
    }

    @Test func revokeAllRefusesEveryRemote() throws {
        var pairing = Pairing()
        let (_, phoneCookie) = try paired(&pairing)
        let (_, tabletCookie) = try paired(&pairing)

        pairing.revokeAll()

        #expect(pairing.remotes.isEmpty)
        #expect(pairing.check(request(cookie: phoneCookie), now: t0) == .refused(.notPaired))
        #expect(pairing.check(request(cookie: tabletCookie), now: t0) == .refused(.notPaired))
    }

    @Test func aRemoteCanUnpairItself() throws {
        var pairing = Pairing()
        let (phone, cookie) = try paired(&pairing)

        #expect(pairing.unpair(request(cookie: cookie, origin: "https://evil.example")) == nil)
        #expect(pairing.unpair(request(cookie: cookie))?.id == phone.id)

        #expect(pairing.remotes.isEmpty)
        #expect(pairing.check(request(cookie: cookie), now: t0) == .refused(.notPaired))
        #expect(Pairing.clearedCookie.hasPrefix(cookie.prefix { $0 != "=" } + "=;"))
        #expect(Pairing.clearedCookie.contains("Max-Age=0"))
    }

    @Test func remembersWhenEachRemotePairedAndWasLastUsed() throws {
        var pairing = Pairing()
        let (remote, cookie) = try paired(&pairing)
        #expect(remote.pairedAt == t0)
        #expect(remote.lastSeen == t0)

        _ = pairing.check(request(cookie: cookie), now: t0 + 600)

        #expect(pairing.remotes.first?.pairedAt == t0)
        #expect(pairing.remotes.first?.lastSeen == t0 + 600)
    }

    @Test func aReloadedPairingStillKnowsItsRemotes() throws {
        var pairing = Pairing()
        let (remote, cookie) = try paired(&pairing)

        var reloaded = try Pairing(saved: pairing.saved())

        #expect(reloaded.remotes == [remote])
        guard case .paired = reloaded.check(request(cookie: cookie), now: t0) else { Issue.record("refused"); return }
        #expect(reloaded.check(request(cookie: cookie, login: "partner@example.com"), now: t0) == .refused(.otherLogin))
    }

    @Test func savesOnlyAHashOfEachToken() throws {
        var pairing = Pairing()
        let (_, cookie) = try paired(&pairing)
        let token = String(cookie.drop { $0 != "=" }.dropFirst())

        let saved = String(decoding: pairing.saved(), as: UTF8.self)

        #expect(!token.isEmpty)
        #expect(!saved.contains(token))
    }

    @Test func aRestartDropsTheLiveCode() throws {
        var pairing = Pairing()
        let code = pairing.newCode(now: t0)

        var reloaded = try Pairing(saved: pairing.saved())

        #expect(reloaded.pair(request(), code: code.digits, now: t0) == .refused(.noCode))
    }
}
