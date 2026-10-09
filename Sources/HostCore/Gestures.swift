/// One gesture event to post, shaped like the trackpad's: a private `CGEvent` of type 29 whose subtype
/// and fields are set by number (docs/adr/0001).
public struct GestureEvent: Equatable, Sendable {
    public var kind: Kind
    public var phase: Phase

    public init(_ kind: Kind, phase: Phase) {
        self.kind = kind
        self.phase = phase
    }

    public enum Kind: Equatable, Sendable {
        /// Change in magnification, as AppKit's `magnification`.
        case magnify(Double)
        /// Degrees, counter-clockwise positive, as AppKit's `rotation`.
        case rotate(Double)
        case smartZoom
    }

    /// `CGGesturePhase` values; a one-shot has none.
    public enum Phase: Int64, Sendable {
        case none = 0, began = 1, changed = 2, ended = 4, cancelled = 8
    }
}

/// Turns the Remote's Gesture commands into gesture events. At most one Gesture is open at a time:
/// a delta for another one first cancels it.
public struct Gestures: Sendable {
    /// Whether the Dock Gestures follow the fingers or happen at once (`MacTrackpadSettings.followsFingers`).
    public let followsFingers: Bool
    private var open: Gesture?

    public init(followsFingers: Bool) {
        self.followsFingers = followsFingers
    }

    public mutating func apply(_ command: Command) -> [GestureEvent] {
        switch command {
        case let .gesture(gesture, delta):
            guard let kind = Self.kind(gesture, delta) else { return [] }
            var events = open == gesture ? [] : cancel()
            events.append(GestureEvent(kind, phase: open == gesture ? .changed : .began))
            open = gesture
            return events
        case let .gestureEnd(gesture, completes):
            guard open == gesture, let kind = Self.kind(gesture, 0) else { return [] }
            open = nil
            return [GestureEvent(kind, phase: completes ? .ended : .cancelled)]
        case .gestureAction(.smartZoom):
            return [GestureEvent(.smartZoom, phase: .none)]
        default:
            return []
        }
    }

    /// Cancels the open Gesture, if any: the fingers touched down again, or the Remote went away.
    public mutating func cancel() -> [GestureEvent] {
        guard let gesture = open, let kind = Self.kind(gesture, 0) else { return [] }
        open = nil
        return [GestureEvent(kind, phase: .cancelled)]
    }

    /// The event a Gesture posts; nil for those the Host doesn't post yet.
    private static func kind(_ gesture: Gesture, _ delta: Double) -> GestureEvent.Kind? {
        switch gesture {
        case .pinch: .magnify(delta)
        case .rotate: .rotate(delta)
        default: nil
        }
    }
}
