/// One scroll-wheel event to post, shaped like a trackpad's: whole-pixel deltas plus the gesture
/// and momentum phases (CGEvent fields 99 and 123) that apps use for smooth scrolling and overscroll.
public struct ScrollEvent: Equatable, Sendable {
    public var dx: Int
    public var dy: Int
    public var phase: Phase
    public var momentum: Momentum

    public init(dx: Int, dy: Int, phase: Phase = .none, momentum: Momentum = .none) {
        self.dx = dx
        self.dy = dy
        self.phase = phase
        self.momentum = momentum
    }

    /// The deltas for the gesture-scroll event (type 29, subtype 6) a trackpad sends with each scroll
    /// while the fingers are down, which lets Safari and Preview swipe between pages; nil while coasting.
    /// Scaled as Mac Mouse Fix does, so a swipe is as easy to start as on the trackpad.
    public var gesture: (dx: Double, dy: Double)? {
        guard phase != .none else { return nil }
        return (Double(dx) * Self.gestureScale, Double(dy) * Self.gestureScale)
    }

    public static let gestureScale = 1.67

    /// `CGScrollPhase` values.
    public enum Phase: Int64, Sendable {
        case none = 0, began = 1, changed = 2, ended = 4
    }

    /// `CGMomentumScrollPhase` values.
    public enum Momentum: Int64, Sendable {
        case none = 0, begin = 1, `continue` = 2, end = 3
    }
}

/// Turns the Remote's scroll commands into trackpad-style scroll events, and generates the momentum
/// tail after a flick itself (the Remote only sends the release velocity).
public struct Scroller: Sendable {
    /// Momentum frames are 1/120 s apart; the Host calls `momentumFrame()` at that rate.
    public static let frameMs = 1000.0 / 120.0
    /// Velocity kept per momentum frame.
    public static let decay = 0.95
    /// Momentum stops once a frame would move less than this, in px.
    private static let stopBelow = 0.3

    private var scrolling = false
    /// Momentum velocity in px/ms, and whether its first frame (momentum Begin) is still to come.
    private var coast: (vx: Double, vy: Double, first: Bool)?
    /// Sub-pixel deltas not posted yet; events carry whole pixels.
    private var remainder = (x: 0.0, y: 0.0)

    public init() {}

    /// A scroll delta from the fingers, in pixels.
    public mutating func scroll(dx: Double, dy: Double) -> ScrollEvent {
        let phase: ScrollEvent.Phase = scrolling ? .changed : .began
        scrolling = true
        let (ix, iy) = whole(dx, dy)
        return ScrollEvent(dx: ix, dy: iy, phase: phase)
    }

    /// The fingers lifted, moving at `vx`, `vy` px/ms.
    public mutating func end(vx: Double, vy: Double) -> [ScrollEvent] {
        guard scrolling else { return [] }
        scrolling = false
        remainder = (0, 0)
        let ended = ScrollEvent(dx: 0, dy: 0, phase: .ended)
        guard Self.moves(vx, vy) else {
            // Close with momentum End right away, so apps don't run momentum of their own.
            return [ended, ScrollEvent(dx: 0, dy: 0, momentum: .end)]
        }
        coast = (vx, vy, true)
        return [ended]
    }

    /// The next momentum event, called every 1/120 s; nil when there's no momentum.
    public mutating func momentumFrame() -> ScrollEvent? {
        guard let c = coast else { return nil }
        guard Self.moves(c.vx, c.vy) else {
            coast = nil
            remainder = (0, 0)
            return ScrollEvent(dx: 0, dy: 0, momentum: .end)
        }
        let (ix, iy) = whole(c.vx * Self.frameMs, c.vy * Self.frameMs)
        coast = (c.vx * Self.decay, c.vy * Self.decay, false)
        return ScrollEvent(dx: ix, dy: iy, momentum: c.first ? .begin : .continue)
    }

    /// A finger touched down: stop coasting, as a real trackpad does.
    public mutating func stop() -> [ScrollEvent] {
        guard coast != nil else { return [] }
        coast = nil
        remainder = (0, 0)
        return [ScrollEvent(dx: 0, dy: 0, momentum: .end)]
    }

    /// The Remote went away: end the fingers' scroll if one is open, and any coast, so the next scroll
    /// begins afresh rather than carrying on this one.
    public mutating func cancel() -> [ScrollEvent] {
        var events: [ScrollEvent] = []
        if scrolling { events.append(ScrollEvent(dx: 0, dy: 0, phase: .ended)) }
        if scrolling || coast != nil { events.append(ScrollEvent(dx: 0, dy: 0, momentum: .end)) }
        scrolling = false
        coast = nil
        remainder = (0, 0)
        return events
    }

    /// Whether velocity `vx`, `vy` still moves at least `stopBelow` px in a frame.
    private static func moves(_ vx: Double, _ vy: Double) -> Bool {
        (vx * vx + vy * vy).squareRoot() * frameMs >= stopBelow
    }

    /// Adds a delta to the remainder and takes out the whole pixels.
    private mutating func whole(_ dx: Double, _ dy: Double) -> (Int, Int) {
        remainder.x += dx
        remainder.y += dy
        let ix = remainder.x.rounded(), iy = remainder.y.rounded()
        remainder.x -= ix
        remainder.y -= iy
        return (Int(ix), Int(iy))
    }
}
