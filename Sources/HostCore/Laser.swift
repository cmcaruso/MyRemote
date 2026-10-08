import CoreGraphics
import Foundation

/// Where the Laser's dot is drawn while the Remote holds it.
///
/// Each hold starts the dot in the centre of one display (the one with the cursor) and keeps it on
/// that display. The Remote's deltas move a target; the dot eases toward it, so motion that arrives
/// in bursts over the network still glides. Points are in global display coordinates, like `Pointer`.
public struct Laser: Sendable {
    /// How far inside the display's edge the dot's centre stays, about the dot's radius.
    public static let margin = 9.0
    /// The easing's time constant, in seconds: the dot covers 63% of the way to the target in this long.
    public static let smoothing = 0.025

    /// The display the dot is on; nil while it's hidden.
    public private(set) var display: CGRect?
    public private(set) var position = CGPoint.zero
    private var target = CGPoint.zero

    public init() {}

    /// Shows the dot in the centre of the display containing `cursor` (or the first display).
    public mutating func start(cursor: CGPoint, displays: [CGRect]) {
        guard let rect = displays.first(where: { $0.contains(cursor) }) ?? displays.first else { return }
        display = rect
        target = CGPoint(x: rect.midX, y: rect.midY)
        position = target
    }

    /// Moves the target by a delta, kept on the display.
    public mutating func move(dx: Double, dy: Double) {
        guard let display else { return }
        let inset = display.insetBy(dx: min(Self.margin, display.width / 2), dy: min(Self.margin, display.height / 2))
        target.x = min(max(target.x + dx, inset.minX), inset.maxX)
        target.y = min(max(target.y + dy, inset.minY), inset.maxY)
    }

    /// Eases the dot toward the target over `dt` seconds and returns where to draw it.
    public mutating func step(dt: Double) -> CGPoint {
        let k = 1 - exp(-max(dt, 0) / Self.smoothing)
        position.x += (target.x - position.x) * k
        position.y += (target.y - position.y) * k
        return position
    }

    public mutating func end() {
        display = nil
    }
}
