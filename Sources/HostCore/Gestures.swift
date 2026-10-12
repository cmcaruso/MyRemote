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
        /// Swipe between pages: back or forward, a Began with the direction then an Ended.
        case pageSwipe(back: Bool)
    }

    /// `CGGesturePhase` values; a one-shot has none.
    public enum Phase: Int64, Sendable {
        case none = 0, began = 1, changed = 2, ended = 4, cancelled = 8
    }
}

/// One dock-swipe event to post: the Dock's own gesture for Mission Control, App Exposé, Spaces, Show
/// Desktop and Apps, which it plays following the fingers (docs/adr/0001).
public struct DockSwipe: Equatable, Sendable {
    public var motion: Motion
    /// Where the swipe has got to, in the Dock's units: vertical, −1 is Mission Control all the way and
    /// +1 App Exposé; pinch, +1 Show Desktop and −1 Apps (field 136, "inverted", left at 0); horizontal,
    /// one Space is `1 + 1/(spaces − 1)`, negative toward the Space on the left.
    public var offset: Double
    public var phase: GestureEvent.Phase
    /// On Ended or Cancelled, how fast the fingers left: the last change × 100, as Mac Mouse Fix sends it.
    public var exitSpeed: Double

    public init(_ motion: Motion, offset: Double, phase: GestureEvent.Phase, exitSpeed: Double = 0) {
        self.motion = motion
        self.offset = offset
        self.phase = phase
        self.exitSpeed = exitSpeed
    }

    public enum Motion: Int64, Sendable {
        case horizontal = 1, vertical = 2, pinch = 3
    }
}

/// A Dock Gesture done at once, where dock swipes aren't posted: a Dock call, or ⌃← / ⌃→ for Spaces.
public enum DockAction: Equatable, Sendable {
    case missionControl, appExpose, showDesktop, apps, spaceLeft, spaceRight
}

/// What a Gesture command turns into.
public enum GestureOutput: Equatable, Sendable {
    case event(GestureEvent)
    case dockSwipe(DockSwipe)
    case dockAction(DockAction)
    /// Notification Center, which no gesture event opens: the Host presses the menu-bar clock.
    case notificationCenter
    /// Look up, which needs a force click or a real three-finger tap: the Host presses its shortcut, ⌃⌘D.
    case lookUp
}

/// Turns the Remote's Gesture commands into gesture events, dock swipes or Dock actions. At most one
/// Gesture is open at a time: a delta for another one first cancels it.
public struct Gestures: Sendable {
    /// Whether the Dock Gestures follow the fingers (`MacTrackpadSettings.followsFingers`); if not, they
    /// happen at once when they complete.
    public let followsFingers: Bool
    private var open: Gesture?
    /// The open Gesture's progress in the Remote's units, summed.
    private var progress = 0.0
    /// The open dock swipe's offset, its last change, and the Dock units per unit of progress.
    private var offset = 0.0
    private var lastChange = 0.0
    private var scale = 1.0

    public init(followsFingers: Bool) {
        self.followsFingers = followsFingers
    }

    /// - Parameter spaces: how many Spaces the active display has, for the Spaces swipe's units.
    public mutating func apply(_ command: Command, spaces: Int = 2) -> [GestureOutput] {
        switch command {
        case let .gesture(gesture, delta):
            let continuing = open == gesture
            var outputs = continuing ? [] : cancel()
            if let kind = Self.kind(gesture, delta) {
                open = gesture
                return outputs + [.event(GestureEvent(kind, phase: continuing ? .changed : .began))]
            }
            if !continuing {
                open = gesture
                progress = 0
                offset = 0
                scale = Self.scale(gesture, spaces: spaces)
            }
            progress += delta
            guard followsFingers, let motion = Self.motion(gesture) else { return outputs }
            let change = delta * scale
            guard change != 0 || !continuing else { return outputs }
            offset += change
            lastChange = change
            outputs.append(.dockSwipe(DockSwipe(motion, offset: offset, phase: continuing ? .changed : .began)))
            return outputs
        case let .gestureEnd(gesture, completes):
            guard open == gesture else { return [] }
            open = nil
            if let kind = Self.kind(gesture, 0) {
                return [.event(GestureEvent(kind, phase: completes ? .ended : .cancelled))]
            }
            if followsFingers, let motion = Self.motion(gesture) {
                return [.dockSwipe(DockSwipe(motion, offset: offset, phase: completes ? .ended : .cancelled,
                                             exitSpeed: lastChange * 100))]
            }
            guard completes, let action = Self.action(gesture, progress: progress) else { return [] }
            return [.dockAction(action)]
        case .gestureAction(.smartZoom):
            return [.event(GestureEvent(.smartZoom, phase: .none))]
        case let .gestureAction(action) where action == .pageBack || action == .pageForward:
            let kind = GestureEvent.Kind.pageSwipe(back: action == .pageBack)
            return [.event(GestureEvent(kind, phase: .began)), .event(GestureEvent(kind, phase: .ended))]
        case .gestureAction(.notificationCenter):
            return [.notificationCenter]
        case .gestureAction(.lookUp):
            return [.lookUp]
        default:
            return []
        }
    }

    /// Cancels the open Gesture, if any: the fingers touched down again, or the Remote went away.
    public mutating func cancel() -> [GestureOutput] {
        guard let gesture = open else { return [] }
        open = nil
        if let kind = Self.kind(gesture, 0) { return [.event(GestureEvent(kind, phase: .cancelled))] }
        guard followsFingers, let motion = Self.motion(gesture) else { return [] }
        return [.dockSwipe(DockSwipe(motion, offset: offset, phase: .cancelled))]
    }

    /// The app gesture event a Gesture posts; nil for the Dock Gestures.
    private static func kind(_ gesture: Gesture, _ delta: Double) -> GestureEvent.Kind? {
        switch gesture {
        case .pinch: .magnify(delta)
        case .rotate: .rotate(delta)
        default: nil
        }
    }

    private static func motion(_ gesture: Gesture) -> DockSwipe.Motion? {
        switch gesture {
        case .missionControl, .appExpose: .vertical
        case .spaces: .horizontal
        case .showDesktop, .apps: .pinch
        case .pinch, .rotate: nil
        }
    }

    /// Dock units per unit of the Remote's progress, signed. For Spaces, the Remote's 1.0 is one Space,
    /// fingers to the right (toward the Space on the left) positive.
    private static func scale(_ gesture: Gesture, spaces: Int) -> Double {
        switch gesture {
        case .missionControl, .apps: -1
        case .appExpose, .showDesktop: 1
        case .spaces: -(1 + 1 / Double(max(spaces, 2) - 1))
        case .pinch, .rotate: 1
        }
    }

    /// What a Dock Gesture does at once; Spaces goes the way the fingers went.
    private static func action(_ gesture: Gesture, progress: Double) -> DockAction? {
        switch gesture {
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .apps: .apps
        case .spaces: progress > 0 ? .spaceLeft : progress < 0 ? .spaceRight : nil
        case .pinch, .rotate: nil
        }
    }
}
