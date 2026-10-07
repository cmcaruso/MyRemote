import AppKit
import CoreGraphics
import HostCore

/// Turns commands into input on the Mac, posted at the HID tap like real hardware.
@MainActor
final class Injector {
    /// A private source keeps the Host's modifier state apart from keys held on the Mac itself.
    private let source = CGEventSource(stateID: .privateState)
    private var pointer = Pointer()
    private var scroller = Scroller()
    private var momentum: Task<Void, Never>?
    /// The left button is down for a drag, so moves post `leftMouseDragged`.
    private var buttonHeld = false

    init() {
        // Don't freeze the Mac's own trackpad after each posted event.
        source?.localEventsSuppressionInterval = 0
    }

    func apply(_ command: Command) {
        switch command {
        case let .move(dx, dy):
            move(dx: dx, dy: dy)
        case let .click(button, count):
            stopMomentum()
            postButton(button, down: true, count: count)
            postButton(button, down: false, count: count)
        case .buttonDown:
            stopMomentum()
            buttonHeld = true
            postButton(.left, down: true, count: 1)
        case .buttonUp:
            release()
        case let .scroll(dx, dy):
            post(scroller.scroll(dx: dx, dy: dy))
        case let .scrollEnd(vx, vy):
            scroller.end(vx: vx, vy: vy).forEach(post)
            startMomentum()
        case .touchDown:
            stopMomentum()
        case let .mediaKey(key):
            postMediaKey(key, down: true)
            postMediaKey(key, down: false)
        case .setVolume:
            break // the Host sets volume through CoreAudio, not input events
        }
    }

    /// A Remote went away: never leave the button stuck down or the page coasting.
    func remoteLeft() {
        release()
        stopMomentum()
    }

    private func release() {
        guard buttonHeld else { return }
        buttonHeld = false
        postButton(.left, down: false, count: 1)
    }

    private func move(dx: Double, dy: Double) {
        let point = pointer.move(from: cursor(), by: CGVector(dx: dx, dy: dy), displays: activeDisplays())
        let type: CGEventType = buttonHeld ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event.post(tap: .cghidEventTap)
    }

    private func postButton(_ button: Command.Button, down: Bool, count: Int) {
        let type: CGEventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor(),
                                  mouseButton: button == .left ? .left : .right) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        event.post(tap: .cghidEventTap)
    }

    /// A media key goes out as the system-defined event the keyboard's media row sends (subtype 8,
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`), so the system routes it and shows its HUD.
    private func postMediaKey(_ key: MediaKey, down: Bool) {
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: key.eventData(down: down), data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func post(_ scroll: ScrollEvent) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(scroll.dy), wheel2: Int32(scroll.dx), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(scroll.dy))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(scroll.dx))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(scroll.dy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(scroll.dx))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scroll.phase.rawValue)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: scroll.momentum.rawValue)
        event.post(tap: .cghidEventTap)
    }

    /// Posts the Scroller's momentum frames every 1/120 s until it runs out or a touch stops it.
    private func startMomentum() {
        momentum?.cancel()
        momentum = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled, let self, let frame = self.scroller.momentumFrame() {
                self.post(frame)
                next += .microseconds(Int64(Scroller.frameMs * 1000))
                try? await clock.sleep(until: next)
            }
        }
    }

    private func stopMomentum() {
        momentum?.cancel()
        momentum = nil
        scroller.stop().forEach(post)
    }

    private func cursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func activeDisplays() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
