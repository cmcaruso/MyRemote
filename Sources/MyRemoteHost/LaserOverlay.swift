import AppKit
import HostCore
import QuartzCore

/// Draws the Laser: a glowing red dot in a click-through panel above everything, full-screen
/// presentations and every Space included. It never touches the real cursor.
///
/// Set up as the Laser prototype proved: one display-sized panel per display, at `.screenSaver` level,
/// joining all Spaces, with the dot as a layer moved without animation.
@MainActor
final class LaserOverlay {
    private static let dotSize = 18.0
    private static let frameSeconds = 1.0 / 120

    private var laser = Laser()
    /// Panels by display, made on first use and dropped when the displays change.
    private var panels: [CGDirectDisplayID: (panel: NSPanel, dot: CALayer)] = [:]
    private var shown: (id: CGDirectDisplayID, bounds: CGRect)?
    private var ticker: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.end()
                self?.panels.values.forEach { $0.panel.orderOut(nil) }
                self?.panels = [:]
            }
        }
    }

    func apply(_ command: Command) {
        switch command {
        case .laserStart: start()
        case let .laserMove(dx, dy): laser.move(dx: dx, dy: dy)
        case .laserEnd: end()
        default: break
        }
    }

    private func start() {
        let displays = Self.displays()
        laser.start(cursor: CGEvent(source: nil)?.location ?? .zero, displays: displays.map(\.bounds))
        guard let bounds = laser.display, let id = displays.first(where: { $0.bounds == bounds })?.id,
              let (panel, dot) = panel(for: id) else { return }
        if let shown, shown.id != id { panels[shown.id]?.panel.orderOut(nil) }
        shown = (id, bounds)
        draw(dot, at: laser.position, on: bounds)
        dot.isHidden = false
        panel.orderFrontRegardless()
        tick()
    }

    func end() {
        ticker?.cancel()
        ticker = nil
        laser.end()
        if let shown { panels[shown.id]?.panel.orderOut(nil) }
        shown = nil
    }

    /// Eases the dot toward its target every 1/120 s while it's shown. A timer rather than a display
    /// link: `NSScreen.displayLink` drops to 30 Hz for every screen when a 30 Hz display is attached.
    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled, let self, let shown = self.shown, let dot = self.panels[shown.id]?.dot {
                try? await clock.sleep(until: last + .seconds(Self.frameSeconds))
                let now = clock.now
                let point = self.laser.step(dt: Double((now - last) / .seconds(1)))
                last = now
                self.draw(dot, at: point, on: shown.bounds)
            }
        }
    }

    /// Moves the dot to a global display point; the panel's layer has its origin bottom-left.
    private func draw(_ dot: CALayer, at point: CGPoint, on bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.position = CGPoint(x: point.x - bounds.minX, y: bounds.maxY - point.y)
        CATransaction.commit()
    }

    private func panel(for id: CGDirectDisplayID) -> (NSPanel, CALayer)? {
        if let made = panels[id] { return made }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return nil }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        // canJoinAllSpaces is the one that puts it over full-screen Spaces; the rest keep it out of the way.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setFrame(screen.frame, display: false)

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        let view = NSView(frame: root.frame)
        view.wantsLayer = true
        view.layer = root
        panel.contentView = view

        let dot = CALayer()
        let red = NSColor(srgbRed: 1, green: 0.13, blue: 0.1, alpha: 1).cgColor
        dot.bounds = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
        dot.cornerRadius = Self.dotSize / 2
        dot.backgroundColor = red
        dot.shadowColor = red
        dot.shadowOpacity = 1
        dot.shadowRadius = 7
        dot.shadowOffset = .zero
        dot.borderColor = NSColor(white: 1, alpha: 0.7).cgColor
        dot.borderWidth = 1.5
        dot.contentsScale = screen.backingScaleFactor
        root.addSublayer(dot)

        panels[id] = (panel, dot)
        return (panel, dot)
    }

    private static func displays() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
