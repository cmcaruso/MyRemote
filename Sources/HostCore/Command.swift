import Foundation

/// A command the Remote sends the Host, one per WebSocket text frame.
///
/// Wire format is compact JSON keyed by `t`:
/// - `{"t":"m","dx":1.5,"dy":-2}`: move the pointer by a relative delta, already accelerated by the Remote.
/// - `{"t":"c","b":0,"n":1}`: click; `b` 0 left / 1 right, `n` the click count (2 = double-click).
/// - `{"t":"d"}` / `{"t":"u"}`: left button down / up, for dragging.
/// - `{"t":"s","dx":0,"dy":-12}`: scroll by a pixel delta, natural direction (content follows the finger).
/// - `{"t":"se","vx":0,"vy":-1.2}`: scroll ended; release velocity in px/ms for the Host's momentum, 0 for none.
/// - `{"t":"x"}`: a finger touched down; stops any momentum, like touching a real trackpad.
/// - `{"t":"k","k":"play"}`: press a media key: `play`, `next`, `prev`, `volup`, `voldown`, `mute`.
/// - `{"t":"v","v":0.4}`: set the output volume, 0 to 1 (clamped).
/// - `{"t":"tx","bs":2,"s":"lo"}`: Keyboard Mode typing; press Backspace `bs` times, then type `s` as is.
/// - `{"t":"kp","k":"left","m":["cmd"]}`: press a named `Key` with modifiers (`cmd`, `opt`, `ctrl`, `shift`; `m` optional).
/// - `{"t":"kp","c":"z","m":["cmd"]}`: press the key that types character `c` in the Mac's layout, with modifiers.
/// - `{"t":"as"}`: one tap of the App switcher (⌘ held for the Remote, Tab pressed).
/// - `{"t":"ls"}` / `{"t":"le"}`: the Laser zone is held / released: show / hide the Laser.
/// - `{"t":"l","dx":3,"dy":-1}`: move the Laser by a relative delta in points, already scaled by the Remote.
/// - `{"t":"g","g":"pinch","d":0.04}`: a continuous `Gesture` moved by `d`; the first frame after an end begins it.
/// - `{"t":"ge","g":"pinch","ok":true}`: the fingers lifted; `ok` says whether the Gesture completes.
/// - `{"t":"ga","a":"smartZoom"}`: a one-shot `GestureAction`.
public enum Command: Equatable, Sendable {
    case move(dx: Double, dy: Double)
    case click(Button, count: Int)
    case buttonDown
    case buttonUp
    case scroll(dx: Double, dy: Double)
    case scrollEnd(vx: Double, vy: Double)
    case touchDown
    case mediaKey(MediaKey)
    case setVolume(Double)
    case type(backspaces: Int, text: String)
    case key(Key, KeyFlags)
    case character(String, KeyFlags)
    case appSwitcher
    case laserStart
    case laserMove(dx: Double, dy: Double)
    case laserEnd
    case gesture(Gesture, delta: Double)
    case gestureEnd(Gesture, completes: Bool)
    case gestureAction(GestureAction)

    public enum Button: Sendable {
        case left, right
    }
}

/// A continuous Gesture the Remote recognised, named on the wire. Units of its deltas: pinch, the change
/// in magnification (0.04 = 4 % larger); rotate, degrees counter-clockwise; the Dock Gestures, progress,
/// where 1.0 = all the way = half the pad of travel (`spaces` signed, negative = fingers to the left, and
/// 1.0 = one Space).
public enum Gesture: String, Sendable {
    case pinch, rotate, missionControl, appExpose, spaces, showDesktop, apps
}

/// A one-shot Gesture.
public enum GestureAction: String, Sendable {
    case smartZoom, lookUp, notificationCenter, pageBack, pageForward
}

extension Command {
    /// Decodes one frame. Returns nil for anything malformed or unknown, so a bad frame is skipped, never fatal.
    public init?(decoding text: String) {
        guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(text.utf8)) else { return nil }
        switch frame.t {
        case "m":
            guard let dx = frame.dx, let dy = frame.dy else { return nil }
            self = .move(dx: dx, dy: dy)
        case "c":
            guard let b = frame.b, let n = frame.n, n >= 1 else { return nil }
            switch b {
            case 0: self = .click(.left, count: n)
            case 1: self = .click(.right, count: n)
            default: return nil
            }
        case "d":
            self = .buttonDown
        case "u":
            self = .buttonUp
        case "s":
            guard let dx = frame.dx, let dy = frame.dy else { return nil }
            self = .scroll(dx: dx, dy: dy)
        case "se":
            guard let vx = frame.vx, let vy = frame.vy else { return nil }
            self = .scrollEnd(vx: vx, vy: vy)
        case "x":
            self = .touchDown
        case "k":
            guard let k = frame.k, let key = MediaKey(rawValue: k) else { return nil }
            self = .mediaKey(key)
        case "v":
            guard let v = frame.v else { return nil }
            self = .setVolume(min(max(v, 0), 1))
        case "tx":
            guard let bs = frame.bs, bs >= 0, let s = frame.s else { return nil }
            self = .type(backspaces: bs, text: s)
        case "kp":
            guard let flags = KeyFlags(wire: frame.m ?? []) else { return nil }
            switch (frame.k, frame.c) {
            case let (k?, nil):
                guard let key = Key(rawValue: k) else { return nil }
                self = .key(key, flags)
            case let (nil, c?):
                guard c.count == 1 else { return nil }
                self = .character(c, flags)
            default:
                return nil
            }
        case "as":
            self = .appSwitcher
        case "ls":
            self = .laserStart
        case "l":
            guard let dx = frame.dx, let dy = frame.dy else { return nil }
            self = .laserMove(dx: dx, dy: dy)
        case "le":
            self = .laserEnd
        case "g":
            guard let g = frame.g, let gesture = Gesture(rawValue: g), let d = frame.d else { return nil }
            self = .gesture(gesture, delta: d)
        case "ge":
            guard let g = frame.g, let gesture = Gesture(rawValue: g), let ok = frame.ok else { return nil }
            self = .gestureEnd(gesture, completes: ok)
        case "ga":
            guard let a = frame.a, let action = GestureAction(rawValue: a) else { return nil }
            self = .gestureAction(action)
        default:
            return nil
        }
    }
}

private struct Frame: Decodable {
    var t: String
    var dx: Double?
    var dy: Double?
    var b: Int?
    var n: Int?
    var vx: Double?
    var vy: Double?
    var k: String?
    var v: Double?
    var bs: Int?
    var s: String?
    var c: String?
    var m: [String]?
    var g: String?
    var d: Double?
    var ok: Bool?
    var a: String?
}
