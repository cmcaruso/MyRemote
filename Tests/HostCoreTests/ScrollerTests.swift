import HostCore
import Testing

@Suite("Scrolling like a trackpad")
struct ScrollerTests {
    @Test func firstDeltaBeginsTheGestureAndLaterOnesChangeIt() {
        var scroller = Scroller()
        #expect(scroller.scroll(dx: 0, dy: -12) == ScrollEvent(dx: 0, dy: -12, phase: .began))
        #expect(scroller.scroll(dx: 3, dy: -7) == ScrollEvent(dx: 3, dy: -7, phase: .changed))
    }

    @Test func carriesFractionsSoSlowScrollingStillMoves() {
        var scroller = Scroller()
        let events = (0..<5).map { _ in scroller.scroll(dx: 0.4, dy: -0.4) }
        // 5 × 0.4 px = 2 px in total, none of it lost to truncation.
        #expect(events.map(\.dy).reduce(0, +) == -2)
        #expect(events.map(\.dx).reduce(0, +) == 2)
    }

    @Test func releasingWithoutVelocityEndsTheGestureWithNoMomentum() {
        var scroller = Scroller()
        _ = scroller.scroll(dx: 0, dy: -12)
        // Momentum End right away, so apps don't run their own momentum.
        #expect(scroller.end(vx: 0, vy: 0) == [
            ScrollEvent(dx: 0, dy: 0, phase: .ended),
            ScrollEvent(dx: 0, dy: 0, momentum: .end),
        ])
        #expect(scroller.momentumFrame() == nil)
        #expect(scroller.scroll(dx: 0, dy: 5).phase == .began)
    }

    @Test func coastsAfterAFlickAndSlowsToAStop() {
        var scroller = Scroller()
        _ = scroller.scroll(dx: 0, dy: -12)
        #expect(scroller.end(vx: 0, vy: -1.2) == [ScrollEvent(dx: 0, dy: 0, phase: .ended)])

        var frames: [ScrollEvent] = []
        while let frame = scroller.momentumFrame() { frames.append(frame) }

        // 1.2 px/ms × 1000/120 ms per frame.
        #expect(frames.first == ScrollEvent(dx: 0, dy: -10, momentum: .begin))
        #expect(frames.dropFirst().dropLast().allSatisfy { $0.momentum == .continue && $0.phase == .none })
        #expect(frames.last == ScrollEvent(dx: 0, dy: 0, momentum: .end))
        // Decaying by 0.95 a frame until under 0.3 px: about 194 px in total.
        let total = frames.map(\.dy).reduce(0, +)
        #expect((-200 ... -188).contains(total))
        #expect(scroller.momentumFrame() == nil)
    }

    @Test func aNewTouchStopsTheCoast() {
        var scroller = Scroller()
        _ = scroller.scroll(dx: 0, dy: -12)
        _ = scroller.end(vx: 0, vy: -1.2)
        _ = scroller.momentumFrame()

        #expect(scroller.stop() == [ScrollEvent(dx: 0, dy: 0, momentum: .end)])
        #expect(scroller.momentumFrame() == nil)
        #expect(scroller.stop() == [])
    }
}
