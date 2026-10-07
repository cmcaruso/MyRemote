import CoreGraphics

/// Where the pointer goes next, given the Remote's relative deltas.
///
/// Points are in global display coordinates (origin top-left of the main display, y down),
/// the space `CGEvent` locations and `CGDisplayBounds` use.
public struct Pointer: Sendable {
    /// Where this pointer has put the cursor, oldest first: the point it started from, then each point posted.
    /// The system reports the cursor rounded and late (a burst of frames outruns it), so as long as the
    /// reported cursor is somewhere on this trail, moving on from the last point keeps every delta.
    private var trail: [CGPoint] = []
    private static let trailLength = 64

    public init() {}

    /// The point to post for a move by `delta` from `cursor`, the cursor's current location.
    public mutating func move(from cursor: CGPoint, by delta: CGVector, displays: [CGRect]) -> CGPoint {
        let onTrail = trail.contains { abs($0.x - cursor.x) < 1.5 && abs($0.y - cursor.y) < 1.5 }
        if !onTrail { trail = [cursor] }  // Something else moved the cursor: follow it.
        let base = trail[trail.count - 1]

        var target = CGPoint(x: base.x + delta.dx, y: base.y + delta.dy)
        if !displays.contains(where: { $0.contains(target) }),
           let display = displays.first(where: { $0.contains(base) }) ?? displays.first {
            // Off every display (past an outer edge, or into a gap between displays): stop at the edge of the one it's on.
            target = CGPoint(
                x: min(max(target.x, display.minX), display.maxX - 1),
                y: min(max(target.y, display.minY), display.maxY - 1)
            )
        }
        trail.append(target)
        if trail.count > Self.trailLength { trail.removeFirst(trail.count - Self.trailLength) }
        return target
    }
}
