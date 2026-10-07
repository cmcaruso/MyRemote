import CoreGraphics
import HostCore

/// Turns commands into input on the Mac, posted at the HID tap like real hardware.
@MainActor
final class Injector {
    /// A private source keeps the Host's modifier state apart from keys held on the Mac itself.
    private let source = CGEventSource(stateID: .privateState)
    private var pointer = Pointer()

    init() {
        // Don't freeze the Mac's own trackpad after each posted event.
        source?.localEventsSuppressionInterval = 0
    }

    func apply(_ command: Command) {
        switch command {
        case let .move(dx, dy): move(dx: dx, dy: dy)
        }
    }

    private func move(dx: Double, dy: Double) {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        let point = pointer.move(from: cursor, by: CGVector(dx: dx, dy: dy), displays: activeDisplays())
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event.post(tap: .cghidEventTap)
    }

    private func activeDisplays() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
