import CoreGraphics

/// Where the pointer goes next, given the Remote's relative deltas.
///
/// Points are in global display coordinates (origin top-left of the main display, y down),
/// the space `CGEvent` locations and `CGDisplayBounds` use.
public struct Pointer: Sendable {
    /// The last point posted. The system reports the cursor on whole pixels, so moving on from
    /// this instead keeps the fractions of slow finger motion.
    private var lastPosted: CGPoint?

    public init() {}

    /// The point to post for a move by `delta` from `cursor`, the cursor's current location.
    public mutating func move(from cursor: CGPoint, by delta: CGVector, displays: [CGRect]) -> CGPoint {
        var base = cursor
        if let last = lastPosted, abs(last.x - cursor.x) < 1.5, abs(last.y - cursor.y) < 1.5 { base = last }

        var target = CGPoint(x: base.x + delta.dx, y: base.y + delta.dy)
        if !displays.contains(where: { $0.contains(target) }),
           let display = displays.first(where: { $0.contains(base) }) ?? displays.first {
            // Off every display (past an outer edge, or into a gap between displays): stop at the edge of the one it's on.
            target = CGPoint(
                x: min(max(target.x, display.minX), display.maxX - 1),
                y: min(max(target.y, display.minY), display.maxY - 1)
            )
        }
        lastPosted = target
        return target
    }
}
