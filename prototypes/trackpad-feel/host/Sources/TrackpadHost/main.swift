// PROTOTYPE (throwaway) for ticket #7 "Does trackpad control feel good enough over the tailnet?"
// Serves ../remote over HTTP and turns WebSocket messages into CGEvents. No auth, no tests, no polish.
//
// Messages (compact JSON, one per WebSocket text frame):
//   {"t":"m","dx":1.5,"dy":-2}           pointer move (already accelerated by the Remote)
//   {"t":"c","b":0|1,"n":1|2}            click (b: 0 left, 1 right; n: click state)
//   {"t":"d"} / {"t":"u"}                left button down / up (drag)
//   {"t":"s","p":"c","dx":0,"dy":3}      scroll changed (Began is sent by the Host on the first one)
//   {"t":"s","p":"e","vx":0,"vy":1.2}    scroll ended, release velocity in px/ms → Host momentum
//   {"t":"p","id":42}                    ping, echoed back verbatim
//   {"t":"cfg",...} / {"t":"stat",...}   tuning params / latency stats, just logged
import CoreGraphics
import Foundation
import Hummingbird
import HummingbirdWebSocket

struct Msg: Decodable {
    var t: String
    var dx: Double?
    var dy: Double?
    var b: Int?
    var n: Int?
    var p: String?
    var vx: Double?
    var vy: Double?
    var decay: Double?
    var ts: Double?   // [DEBUG-lat] phone send time (performance.now ms)
    var age: Double?  // [DEBUG-lat] phone touch event → send, ms
}

/// [DEBUG-lat] One-way delay of motion messages relative to the fastest one seen (cancels the clock offset),
/// plus arrival gaps while a finger is moving.
final class Uplink: @unchecked Sendable {
    var minOff = Double.infinity, lastArrival = 0.0, lastTs = 0.0
    var excess: [Double] = [], gaps: [Double] = [], ages: [Double] = []
    var lastReport = 0.0
    func add(ts: Double, age: Double) {
        let now = Date().timeIntervalSince1970 * 1000
        if ts < lastTs { minOff = .infinity }  // page reloaded
        let off = now - ts
        minOff = min(minOff, off)
        excess.append(off - minOff)
        ages.append(age)
        if ts - lastTs < 60 { gaps.append(now - lastArrival) }  // same stroke: phone sent within 60 ms of the last one
        lastArrival = now
        lastTs = ts
        if now - lastReport > 5000 && excess.count >= 20 { report(now) }
    }
    func report(_ now: Double) {
        func pct(_ a: [Double], _ p: Double) -> String { let s = a.sorted(); return String(format: "%.0f", s[min(s.count - 1, Int(p * Double(s.count)))]) }
        let big = gaps.filter { $0 > 50 }.count
        log("[DEBUG-lat] uplink n=\(excess.count) excess p50=\(pct(excess, 0.5)) p95=\(pct(excess, 0.95)) max=\(pct(excess, 1)) ms | gaps>50ms=\(big)/\(gaps.count) maxgap=\(gaps.isEmpty ? "-" : pct(gaps, 1)) | phone age p50=\(pct(ages, 0.5)) p95=\(pct(ages, 0.95))")
        excess.removeAll(); gaps.removeAll(); ages.removeAll()
        lastReport = now
    }
}
let uplink = Uplink()

func log(_ s: String) {
    let ts = Date().formatted(.dateTime.hour().minute().second())
    print("[\(ts)] \(s)")
    fflush(stdout)
}

actor Injector {
    let src = CGEventSource(stateID: .privateState)
    var carry: CGPoint?  // last posted position, keeps sub-pixel motion
    var buttonHeld = false
    var scrolling = false
    var scrollRemainder = (x: 0.0, y: 0.0)
    var momentum: Task<Void, Never>?

    init() {
        src?.localEventsSuppressionInterval = 0
    }

    func current() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func displays() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).map { CGDisplayBounds($0) }
    }

    func clamp(_ p: CGPoint, from base: CGPoint) -> CGPoint {
        let ds = displays()
        if ds.contains(where: { $0.contains(p) }) { return p }
        let d = ds.first(where: { $0.contains(base) }) ?? ds.first ?? .zero
        return CGPoint(x: min(max(p.x, d.minX), d.maxX - 1), y: min(max(p.y, d.minY), d.maxY - 1))
    }

    func move(_ dx: Double, _ dy: Double) {
        let cur = current()
        var base = cur
        if let c = carry, abs(c.x - cur.x) < 1.5, abs(c.y - cur.y) < 1.5 { base = c }
        let p = clamp(CGPoint(x: base.x + dx, y: base.y + dy), from: base)
        carry = p
        let type: CGEventType = buttonHeld ? .leftMouseDragged : .mouseMoved
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        e.post(tap: .cghidEventTap)
    }

    func button(down: Bool, right: Bool = false, clickState: Int64 = 1) {
        let p = current()
        let type: CGEventType = right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: right ? .right : .left) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: clickState)
        e.post(tap: .cghidEventTap)
    }

    func click(right: Bool, n: Int) {
        stopMomentum()
        button(down: true, right: right, clickState: Int64(n))
        button(down: false, right: right, clickState: Int64(n))
    }

    func press() { stopMomentum(); buttonHeld = true; button(down: true) }
    func release() { if buttonHeld { buttonHeld = false; button(down: false) } }

    /// One pixel-unit scroll event with trackpad-style phases (fields 99 scroll phase, 123 momentum phase).
    func postScroll(dx: Double, dy: Double, phase: Int64, momentum: Int64) {
        scrollRemainder.x += dx
        scrollRemainder.y += dy
        let ix = scrollRemainder.x.rounded(.towardZero), iy = scrollRemainder.y.rounded(.towardZero)
        scrollRemainder.x -= ix
        scrollRemainder.y -= iy
        guard let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                              wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(iy))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(ix))
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: iy)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: ix)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        e.post(tap: .cghidEventTap)
    }

    func scroll(_ dx: Double, _ dy: Double) {
        if !scrolling {
            stopMomentum()
            scrolling = true
            scrollRemainder = (0, 0)
            postScroll(dx: dx, dy: dy, phase: 1, momentum: 0)  // Began
        } else {
            postScroll(dx: dx, dy: dy, phase: 2, momentum: 0)  // Changed
        }
    }

    func scrollEnd(vx: Double, vy: Double, decay: Double) {
        guard scrolling else { return }
        scrolling = false
        postScroll(dx: 0, dy: 0, phase: 4, momentum: 0)  // Ended
        let speed = (vx * vx + vy * vy).squareRoot()
        guard speed > 0.05, decay > 0 else {
            postScroll(dx: 0, dy: 0, phase: 0, momentum: 3)  // close with momentum End so apps don't add their own
            return
        }
        momentum = Task { await self.runMomentum(vx: vx, vy: vy, decay: decay) }
    }

    func runMomentum(vx: Double, vy: Double, decay: Double) async {
        let frameMs = 1000.0 / 120.0
        var v = (x: vx, y: vy)
        var first = true
        while !Task.isCancelled {
            let dx = v.x * frameMs, dy = v.y * frameMs
            if abs(dx) < 0.3 && abs(dy) < 0.3 { break }
            postScroll(dx: dx, dy: dy, phase: 0, momentum: first ? 1 : 2)
            first = false
            v.x *= decay
            v.y *= decay
            try? await Task.sleep(for: .milliseconds(8))
        }
        postScroll(dx: 0, dy: 0, phase: 0, momentum: 3)
        momentum = nil
    }

    func stopMomentum() {
        momentum?.cancel()
        momentum = nil
    }
}

let injector = Injector()
let remoteDir = CommandLine.arguments.dropFirst().first ?? "../remote"
let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8484") ?? 8484

log("Accessibility (PostEvent) granted: \(CGPreflightPostEventAccess())")
if !CGPreflightPostEventAccess() {
    _ = CGRequestPostEventAccess()
    log("Requested Accessibility. Grant it to the app running this process, then restart.")
}

let router = Router()
router.add(middleware: FileMiddleware(remoteDir, searchForIndexHtml: true))

let wsRouter = Router(context: BasicWebSocketRequestContext.self)
wsRouter.ws("/ws") { inbound, outbound, context in
    log("Remote connected")
    let decoder = JSONDecoder()
    for try await message in inbound.messages(maxSize: 1 << 16) {
        guard case .text(let text) = message,
              let m = try? decoder.decode(Msg.self, from: Data(text.utf8)) else { continue }
        if let ts = m.ts { uplink.add(ts: ts, age: m.age ?? 0) }
        switch m.t {
        case "m": await injector.move(m.dx ?? 0, m.dy ?? 0)
        case "c": await injector.click(right: m.b == 1, n: m.n ?? 1)
        case "d": await injector.press()
        case "u": await injector.release()
        case "s":
            if m.p == "e" {
                await injector.scrollEnd(vx: m.vx ?? 0, vy: m.vy ?? 0, decay: m.decay ?? 0.95)
            } else {
                await injector.scroll(m.dx ?? 0, m.dy ?? 0)
            }
        case "p": try await outbound.write(.text(text))
        case "cfg", "stat": log("\(m.t): \(text)")
        default: break
        }
    }
    await injector.release()
    log("Remote disconnected")
}

let app = Application(
    router: router,
    server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
    configuration: .init(address: .hostname("127.0.0.1", port: port))
)
log("Serving \(remoteDir) on http://127.0.0.1:\(port), WebSocket at /ws")
try await app.runService()
