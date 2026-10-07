import Foundation

/// A command the Remote sends the Host, one per WebSocket text frame.
///
/// Wire format is compact JSON keyed by `t`:
/// - `{"t":"m","dx":1.5,"dy":-2}`: move the pointer by a relative delta, already accelerated by the Remote.
public enum Command: Equatable, Sendable {
    case move(dx: Double, dy: Double)
}

extension Command {
    /// Decodes one frame. Returns nil for anything malformed or unknown, so a bad frame is skipped, never fatal.
    public init?(decoding text: String) {
        guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(text.utf8)) else { return nil }
        switch frame.t {
        case "m":
            guard let dx = frame.dx, let dy = frame.dy else { return nil }
            self = .move(dx: dx, dy: dy)
        default:
            return nil
        }
    }
}

private struct Frame: Decodable {
    var t: String
    var dx: Double?
    var dy: Double?
}
