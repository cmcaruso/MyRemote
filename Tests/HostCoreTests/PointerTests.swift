import CoreGraphics
import HostCore
import Testing

/// Global display coordinates: origin top-left of the main display, y down.
private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Suite("Moving the pointer")
struct PointerTests {
    @Test func movesByTheDeltaWithinADisplay() {
        var pointer = Pointer()
        let p = pointer.move(from: CGPoint(x: 100, y: 100), by: CGVector(dx: 12.5, dy: -4), displays: [main])
        #expect(p == CGPoint(x: 112.5, y: 96))
    }

    @Test func stopsAtTheEdgeOfTheScreen() {
        var pointer = Pointer()
        let p = pointer.move(from: CGPoint(x: 1500, y: 10), by: CGVector(dx: 300, dy: -50), displays: [main])
        #expect(p == CGPoint(x: 1511, y: 0))
    }

    @Test func keepsSubPixelMotionTheCursorLocationRoundsAway() {
        var pointer = Pointer()
        var posted = CGPoint(x: 100, y: 100)
        for _ in 0..<10 {
            // The system reports the cursor on whole pixels.
            let cursor = CGPoint(x: posted.x.rounded(.down), y: posted.y.rounded(.down))
            posted = pointer.move(from: cursor, by: CGVector(dx: 0.3, dy: -0.3), displays: [main])
        }
        #expect(abs(posted.x - 103) < 0.001)
        #expect(abs(posted.y - 97) < 0.001)
    }

    @Test func keepsAllMotionFromABurstTheSystemHasNotCaughtUpWith() {
        // Frames queued behind a Wi-Fi stall arrive at once; the reported cursor lags behind what was posted.
        var pointer = Pointer()
        let start = CGPoint(x: 400, y: 300)
        var posted: [CGPoint] = []
        for i in 0..<20 {
            // Stale for the first frames, then catching up a few posts behind.
            let cursor = i < 5 ? start : posted[i - 4]
            posted.append(pointer.move(from: cursor, by: CGVector(dx: 5, dy: 2.5), displays: [main]))
        }
        #expect(posted.last == CGPoint(x: 500, y: 350))
    }

    @Test func followsTheCursorWhenSomethingElseMovedIt() {
        var pointer = Pointer()
        _ = pointer.move(from: CGPoint(x: 100, y: 100), by: CGVector(dx: 0.5, dy: 0.5), displays: [main])
        // The physical trackpad moved the cursor far away meanwhile.
        let p = pointer.move(from: CGPoint(x: 800, y: 400), by: CGVector(dx: 1, dy: 1), displays: [main])
        #expect(p == CGPoint(x: 801, y: 401))
    }

    @Test func crossesOntoADisplayLeftOfTheMainOne() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        var pointer = Pointer()
        let p = pointer.move(from: CGPoint(x: 5, y: 300), by: CGVector(dx: -40, dy: -10), displays: [main, left])
        #expect(p == CGPoint(x: -35, y: 290))
    }

    @Test func staysOnItsDisplayInsteadOfEnteringAGapBetweenDisplays() {
        // A shorter display to the right leaves an empty corner below it.
        let right = CGRect(x: 1512, y: 0, width: 1280, height: 720)
        var pointer = Pointer()
        let p = pointer.move(from: CGPoint(x: 1500, y: 900), by: CGVector(dx: 30, dy: 0), displays: [main, right])
        #expect(p == CGPoint(x: 1511, y: 900))
    }
}
