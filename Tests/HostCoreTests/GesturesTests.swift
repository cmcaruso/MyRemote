import HostCore
import Testing

@Suite("Posting Gestures as trackpad events")
struct GesturesTests {
    @Test(arguments: [true, false])
    func pinchBeginsChangesAndEnds(_ followsFingers: Bool) {
        var gestures = Gestures(followsFingers: followsFingers)
        #expect(gestures.apply(.gesture(.pinch, delta: 0.04)) == [GestureEvent(.magnify(0.04), phase: .began)])
        #expect(gestures.apply(.gesture(.pinch, delta: 0.02)) == [GestureEvent(.magnify(0.02), phase: .changed)])
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [GestureEvent(.magnify(0), phase: .ended)])
        // The next delta begins a new one.
        #expect(gestures.apply(.gesture(.pinch, delta: -0.01)) == [GestureEvent(.magnify(-0.01), phase: .began)])
    }

    @Test func rotateCarriesDegrees() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gesture(.rotate, delta: 5)) == [GestureEvent(.rotate(5), phase: .began)])
        #expect(gestures.apply(.gesture(.rotate, delta: -2)) == [GestureEvent(.rotate(-2), phase: .changed)])
        #expect(gestures.apply(.gestureEnd(.rotate, completes: true)) == [GestureEvent(.rotate(0), phase: .ended)])
    }

    @Test func anotherGestureCancelsTheOpenOne() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.pinch, delta: 0.04))
        #expect(gestures.apply(.gesture(.rotate, delta: 3)) == [
            GestureEvent(.magnify(0), phase: .cancelled),
            GestureEvent(.rotate(3), phase: .began),
        ])
        // The pinch is no longer open, so its end does nothing.
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [])
    }

    @Test func notCompletingCancels() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.pinch, delta: 0.04))
        #expect(gestures.apply(.gestureEnd(.pinch, completes: false)) == [GestureEvent(.magnify(0), phase: .cancelled)])
    }

    @Test func aStrayEndDoesNothing() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [])
    }

    @Test func cancelClosesTheOpenGestureOnce() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.cancel() == [])
        _ = gestures.apply(.gesture(.rotate, delta: 3))
        #expect(gestures.cancel() == [GestureEvent(.rotate(0), phase: .cancelled)])
        #expect(gestures.cancel() == [])
        #expect(gestures.apply(.gesture(.rotate, delta: 1)) == [GestureEvent(.rotate(1), phase: .began)])
    }

    @Test func smartZoomIsOneEvent() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gestureAction(.smartZoom)) == [GestureEvent(.smartZoom, phase: .none)])
    }

    @Test func otherCommandsPostNothing() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.move(dx: 1, dy: 1)) == [])
    }
}
