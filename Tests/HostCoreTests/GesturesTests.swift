import HostCore
import Testing

@Suite("Posting Gestures as trackpad events")
struct GesturesTests {
    private func event(_ kind: GestureEvent.Kind, _ phase: GestureEvent.Phase) -> GestureOutput {
        .event(GestureEvent(kind, phase: phase))
    }

    private func swipe(_ motion: DockSwipe.Motion, _ offset: Double, _ phase: GestureEvent.Phase, exit: Double = 0) -> GestureOutput {
        .dockSwipe(DockSwipe(motion, offset: offset, phase: phase, exitSpeed: exit))
    }

    // ---------- Pinch, rotate, smart zoom ----------

    @Test(arguments: [true, false])
    func pinchBeginsChangesAndEnds(_ followsFingers: Bool) {
        var gestures = Gestures(followsFingers: followsFingers)
        #expect(gestures.apply(.gesture(.pinch, delta: 0.04)) == [event(.magnify(0.04), .began)])
        #expect(gestures.apply(.gesture(.pinch, delta: 0.02)) == [event(.magnify(0.02), .changed)])
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [event(.magnify(0), .ended)])
        // The next delta begins a new one.
        #expect(gestures.apply(.gesture(.pinch, delta: -0.01)) == [event(.magnify(-0.01), .began)])
    }

    @Test func rotateCarriesDegrees() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gesture(.rotate, delta: 5)) == [event(.rotate(5), .began)])
        #expect(gestures.apply(.gesture(.rotate, delta: -2)) == [event(.rotate(-2), .changed)])
        #expect(gestures.apply(.gestureEnd(.rotate, completes: true)) == [event(.rotate(0), .ended)])
    }

    @Test func anotherGestureCancelsTheOpenOne() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.pinch, delta: 0.04))
        #expect(gestures.apply(.gesture(.rotate, delta: 3)) == [event(.magnify(0), .cancelled), event(.rotate(3), .began)])
        // The pinch is no longer open, so its end does nothing.
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [])
    }

    @Test func notCompletingCancels() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.pinch, delta: 0.04))
        #expect(gestures.apply(.gestureEnd(.pinch, completes: false)) == [event(.magnify(0), .cancelled)])
    }

    @Test func aStrayEndDoesNothing() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gestureEnd(.pinch, completes: true)) == [])
    }

    @Test func cancelClosesTheOpenGestureOnce() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.cancel() == [])
        _ = gestures.apply(.gesture(.rotate, delta: 3))
        #expect(gestures.cancel() == [event(.rotate(0), .cancelled)])
        #expect(gestures.cancel() == [])
        #expect(gestures.apply(.gesture(.rotate, delta: 1)) == [event(.rotate(1), .began)])
    }

    @Test func smartZoomIsOneEvent() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gestureAction(.smartZoom)) == [event(.smartZoom, .none)])
    }

    @Test(arguments: [true, false])
    func aPageSwipeBeginsWithItsDirectionAndEnds(_ followsFingers: Bool) {
        var gestures = Gestures(followsFingers: followsFingers)
        #expect(gestures.apply(.gestureAction(.pageBack)) == [event(.pageSwipe(back: true), .began),
                                                               event(.pageSwipe(back: true), .ended)])
        #expect(gestures.apply(.gestureAction(.pageForward)) == [event(.pageSwipe(back: false), .began),
                                                                  event(.pageSwipe(back: false), .ended)])
    }

    @Test(arguments: [true, false])
    func notificationCenterAndLookUpAreOneShots(_ followsFingers: Bool) {
        var gestures = Gestures(followsFingers: followsFingers)
        #expect(gestures.apply(.gestureAction(.notificationCenter)) == [.notificationCenter])
        #expect(gestures.apply(.gestureAction(.lookUp)) == [.lookUp])
    }

    @Test func otherCommandsPostNothing() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.move(dx: 1, dy: 1)) == [])
    }

    // ---------- The Dock Gestures, following the fingers ----------

    @Test func missionControlSwipesUpAndEndsWithTheExitSpeed() {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gesture(.missionControl, delta: 0.1)) == [swipe(.vertical, -0.1, .began)])
        #expect(gestures.apply(.gesture(.missionControl, delta: 0.15)) == [swipe(.vertical, -0.25, .changed)])
        #expect(gestures.apply(.gestureEnd(.missionControl, completes: true)) == [swipe(.vertical, -0.25, .ended, exit: -15)])
    }

    @Test(arguments: [
        (Gesture.appExpose, DockSwipe.Motion.vertical, 0.3),
        (.showDesktop, .pinch, 0.3),
        (.apps, .pinch, -0.3),
    ])
    func eachDockGestureHasItsMotionAndDirection(_ gesture: Gesture, _ motion: DockSwipe.Motion, _ offset: Double) {
        var gestures = Gestures(followsFingers: true)
        #expect(gestures.apply(.gesture(gesture, delta: 0.3)) == [swipe(motion, offset, .began)])
    }

    @Test func spacesCountsOneSpaceAsTheDockDoes() {
        var gestures = Gestures(followsFingers: true)
        // Five Spaces: one Space is 1 + 1/4 = 1.25. Fingers to the right go toward the Space on the left.
        #expect(gestures.apply(.gesture(.spaces, delta: 0.4), spaces: 5) == [swipe(.horizontal, -0.5, .began)])
        #expect(gestures.apply(.gesture(.spaces, delta: -0.8), spaces: 5) == [swipe(.horizontal, 0.5, .changed)])
    }

    @Test func aSwipeThatDoesNotCompleteIsCancelled() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.missionControl, delta: 0.1))
        #expect(gestures.apply(.gestureEnd(.missionControl, completes: false)) == [swipe(.vertical, -0.1, .cancelled, exit: -10)])
    }

    @Test func aStillFrameAddsNothing() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.apps, delta: 0.1))
        #expect(gestures.apply(.gesture(.apps, delta: 0)) == [])
    }

    @Test func touchingDownCancelsAnOpenSwipe() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.spaces, delta: 0.2))
        #expect(gestures.cancel() == [swipe(.horizontal, -0.4, .cancelled)])
    }

    @Test func switchingFromAPinchToASwipeCancelsThePinch() {
        var gestures = Gestures(followsFingers: true)
        _ = gestures.apply(.gesture(.pinch, delta: 0.1))
        #expect(gestures.apply(.gesture(.missionControl, delta: 0.1)) == [event(.magnify(0), .cancelled), swipe(.vertical, -0.1, .began)])
    }

    // ---------- The Dock Gestures, at once ----------

    @Test(arguments: [
        (Gesture.missionControl, DockAction.missionControl),
        (.appExpose, .appExpose),
        (.showDesktop, .showDesktop),
        (.apps, .apps),
    ])
    func oneShotFiresOnlyWhenTheGestureCompletes(_ gesture: Gesture, _ action: DockAction) {
        var gestures = Gestures(followsFingers: false)
        #expect(gestures.apply(.gesture(gesture, delta: 0.3)) == [])
        #expect(gestures.apply(.gestureEnd(gesture, completes: true)) == [.dockAction(action)])
        _ = gestures.apply(.gesture(gesture, delta: 0.1))
        #expect(gestures.apply(.gestureEnd(gesture, completes: false)) == [])
    }

    @Test func oneShotSpacesGoesTheWayTheFingersWent() {
        var gestures = Gestures(followsFingers: false)
        _ = gestures.apply(.gesture(.spaces, delta: -0.3))
        #expect(gestures.apply(.gestureEnd(.spaces, completes: true)) == [.dockAction(.spaceRight)])
        _ = gestures.apply(.gesture(.spaces, delta: 0.3))
        #expect(gestures.apply(.gestureEnd(.spaces, completes: true)) == [.dockAction(.spaceLeft)])
    }

    @Test func oneShotHasNothingToCancel() {
        var gestures = Gestures(followsFingers: false)
        _ = gestures.apply(.gesture(.missionControl, delta: 0.3))
        #expect(gestures.cancel() == [])
    }
}
