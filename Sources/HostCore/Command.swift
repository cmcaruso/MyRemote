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
public enum Command: Equatable, Sendable {
    case move(dx: Double, dy: Double)
    case click(Button, count: Int)
    case buttonDown
    case buttonUp
    case scroll(dx: Double, dy: Double)
    case scrollEnd(vx: Double, vy: Double)
    case touchDown

    public enum Button: Sendable {
        case left, right
    }
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
}
