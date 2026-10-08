// PROTOTYPE (ticket #12): throwaway. Can a click-through panel draw the Laser above
// full-screen presentations, on every Space? Not production code: no tests, no error handling.
//
// A 🔴 menubar item picks the window level, the Space flags and how the dot moves.
// "Cycle levels" steps through every level every 4 s, with the level's name drawn next to
// the dot, so you can watch from inside a slideshow without reaching the menu.
// Once a second it logs: level, flags, whether macOS says the panel is visible, which
// windows sit above it, and frame timing and CPU.

import AppKit
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)

struct Level { let name: String; let value: NSWindow.Level }
let levels: [Level] = [
    Level(name: "floating (3)", value: .floating),
    Level(name: "statusBar (25)", value: .statusBar),
    Level(name: "popUpMenu (101)", value: .popUpMenu),
    Level(name: "screenSaver (1000)", value: .screenSaver),
    Level(name: "assistiveTechHigh (1500)", value: NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow)))),
    Level(name: "shielding (\(CGShieldingWindowLevel()))", value: NSWindow.Level(Int(CGShieldingWindowLevel()))),
]

struct Flag { let name: String; let value: NSWindow.CollectionBehavior }
let flags: [Flag] = [
    Flag(name: "canJoinAllSpaces", value: .canJoinAllSpaces),
    Flag(name: "fullScreenAuxiliary", value: .fullScreenAuxiliary),
    Flag(name: "stationary", value: .stationary),
    Flag(name: "ignoresCycle", value: .ignoresCycle),
    Flag(name: "fullScreenNone", value: .fullScreenNone),
]

enum Motion: String, CaseIterable { case layer = "Layer in a full-display panel", window = "Small window moved each frame" }

let dotSize: CGFloat = 18
let glow: CGFloat = 14

final class Overlay: NSObject, NSMenuDelegate {
    var levelIndex = 3
    var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    var motion = Motion.layer
    var screenIndex = 0
    var cycling = false
    var shown = true

    var panel: NSPanel!
    let dot = CALayer()
    let label = CATextLayer()
    var link: CADisplayLink?
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var t0 = CACurrentMediaTime()
    var lastFrame: CFTimeInterval = 0
    var frames = 0, drops = 0
    var worstGap: CFTimeInterval = 0
    var lastCPU = cpuSeconds(), lastStats = CACurrentMediaTime()
    var cycleAt = CACurrentMediaTime()

    var screen: NSScreen { NSScreen.screens[min(screenIndex, NSScreen.screens.count - 1)] }

    func start() {
        status.button?.title = "🔴"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        rebuild()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.log("Space changed")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    // Tear the panel down and make a new one, so every setting starts from a clean window.
    func rebuild() {
        link?.invalidate()
        panel?.orderOut(nil)
        let frame: NSRect
        switch motion {
        case .layer: frame = screen.frame
        case .window: frame = NSRect(x: screen.frame.midX, y: screen.frame.midY, width: dotSize + 2 * glow + 240, height: dotSize + 2 * glow)
        }
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = levels[levelIndex].value
        p.collectionBehavior = behavior
        p.isReleasedWhenClosed = false

        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        p.contentView = NSView(frame: root.frame)
        p.contentView!.wantsLayer = true
        p.contentView!.layer = root

        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = NSColor(srgbRed: 1, green: 0.13, blue: 0.1, alpha: 1).cgColor
        dot.shadowColor = dot.backgroundColor
        dot.shadowOpacity = 1
        dot.shadowRadius = glow / 2
        dot.shadowOffset = .zero
        dot.borderColor = NSColor(white: 1, alpha: 0.7).cgColor
        dot.borderWidth = 1.5
        dot.actions = ["position": NSNull()]
        root.addSublayer(dot)

        label.fontSize = 15
        label.foregroundColor = NSColor.white.cgColor
        label.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        label.cornerRadius = 4
        label.contentsScale = screen.backingScaleFactor
        label.actions = ["position": NSNull(), "string": NSNull()]
        root.addSublayer(label)
        updateLabel()

        panel = p
        if shown { p.orderFrontRegardless() }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        frames = 0; drops = 0; worstGap = 0; lastFrame = 0
        rebuildMenu()
        log("rebuilt")
    }

    func updateLabel() {
        label.string = " \(levels[levelIndex].name) · \(motion == .layer ? "layer" : "window") "
        label.frame = CGRect(x: 0, y: 0, width: 240, height: 20)
    }

    @objc func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if lastFrame > 0 {
            let gap = now - lastFrame
            let expected = l.targetTimestamp - l.timestamp
            if gap > expected * 1.5 { drops += 1 }
            worstGap = max(worstGap, gap)
        }
        lastFrame = now
        frames += 1

        // A Lissajous path over the middle 70% of the display, like a hand sweeping a slide.
        let t = now - t0
        let s = screen.frame
        let x = s.width * (0.5 + 0.35 * sin(t * 0.9))
        let y = s.height * (0.5 + 0.35 * sin(t * 1.3 + 0.7))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch motion {
        case .layer:
            dot.position = CGPoint(x: x, y: y)
            label.position = CGPoint(x: x + dotSize + 120, y: y)
        case .window:
            panel.setFrameOrigin(NSPoint(x: s.minX + x - dotSize / 2 - glow, y: s.minY + y - dotSize / 2 - glow))
            dot.position = CGPoint(x: glow + dotSize / 2, y: glow + dotSize / 2)
            label.position = CGPoint(x: dotSize + 2 * glow + 120, y: glow + dotSize / 2)
        }
        CATransaction.commit()

        if cycling && CACurrentMediaTime() - cycleAt > 4 {
            cycleAt = CACurrentMediaTime()
            levelIndex = (levelIndex + 1) % levels.count
            panel.level = levels[levelIndex].value
            updateLabel()
            log("cycle")
        }
        if CACurrentMediaTime() - lastStats >= 1 { stats() }
    }

    func stats() {
        let now = CACurrentMediaTime(), cpu = cpuSeconds()
        let pct = 100 * (cpu - lastCPU) / (now - lastStats)
        print(String(format: "  fps %d  drops %d  worst gap %.1f ms  cpu %.1f%%", frames, drops, worstGap * 1000, pct))
        lastCPU = cpu; lastStats = now
        frames = 0; drops = 0; worstGap = 0
        log("tick")
        control()
    }

    // Scripted runs: write lines like "level 0", "flags canJoinAllSpaces,stationary",
    // "motion window", "screen 1", "hide", "show" to $LASER_CONTROL; read once a second.
    func control() {
        guard let path = ProcessInfo.processInfo.environment["LASER_CONTROL"],
              let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else { return }
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            print("> \(line)")
            switch parts[0] {
            case "level": levelIndex = Int(arg) ?? levelIndex; panel.level = levels[levelIndex].value; updateLabel(); log("level")
            case "flags":
                behavior = []
                for n in arg.split(separator: ",") { if let f = flags.first(where: { $0.name == n }) { behavior.insert(f.value) } }
                rebuild()
            case "motion": motion = arg == "window" ? .window : .layer; rebuild()
            case "screen": screenIndex = Int(arg) ?? 0; rebuild()
            case "hide": if shown { toggleShown() }
            case "show": if !shown { toggleShown() }
            default: break
            }
        }
    }

    func log(_ why: String) {
        guard let panel else { return }
        let names = flags.filter { panel.collectionBehavior.contains($0.value) }.map(\.name).joined(separator: ",")
        let visible = panel.occlusionState.contains(.visible)
        print("[\(why)] level=\(levels[levelIndex].name) flags=[\(names)] motion=\(motion == .layer ? "layer" : "window") screen=\(screenIndex) onActiveSpace=\(panel.isOnActiveSpace) occlusionVisible=\(visible) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        print("   above: \(windowsAbove())")
    }

    // On-screen windows that sit above the panel and overlap its display: anything here hides the dot.
    func windowsAbove() -> String {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], CGWindowID(panel.windowNumber)) as? [[String: Any]] else { return "?" }
        let s = screen.frame
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgScreen = CGRect(x: s.minX, y: primaryHeight - s.maxY, width: s.width, height: s.height)
        let hits = list.compactMap { w -> String? in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.intersects(cgScreen), r.width > 40, r.height > 40 else { return nil }
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            return "\(owner)@\(layer) \(Int(r.width))x\(Int(r.height))"
        }
        return hits.isEmpty ? "nothing" : hits.joined(separator: "; ")
    }

    // MARK: menu

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    func rebuildMenu() {
        let m = status.menu!
        m.removeAllItems()
        let title = NSMenuItem(title: "Laser overlay PROTOTYPE (#12)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        m.addItem(item(shown ? "Hide dot (release)" : "Show dot (hold)", #selector(toggleShown)))
        m.addItem(item(cycling ? "Stop cycling levels" : "Cycle levels every 4 s", #selector(toggleCycle)))
        m.addItem(.separator())
        m.addItem(header("Level"))
        for (i, l) in levels.enumerated() {
            let it = item(l.name, #selector(pickLevel(_:)), tag: i)
            it.state = i == levelIndex ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(header("Collection behaviour"))
        for (i, f) in flags.enumerated() {
            let it = item(f.name, #selector(toggleFlag(_:)), tag: i)
            it.state = behavior.contains(f.value) ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(header("Motion"))
        for (i, mo) in Motion.allCases.enumerated() {
            let it = item(mo.rawValue, #selector(pickMotion(_:)), tag: i)
            it.state = mo == motion ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(header("Display"))
        for (i, s) in NSScreen.screens.enumerated() {
            let it = item(s.localizedName, #selector(pickScreen(_:)), tag: i)
            it.state = i == screenIndex ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(item("Quit", #selector(quit)))
    }

    func header(_ s: String) -> NSMenuItem {
        let it = NSMenuItem(title: s, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    func item(_ s: String, _ sel: Selector, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: s, action: sel, keyEquivalent: "")
        it.target = self
        it.tag = tag
        return it
    }

    @objc func toggleShown() {
        shown.toggle()
        if shown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        log(shown ? "show" : "hide")
    }
    @objc func toggleCycle() { cycling.toggle(); cycleAt = CACurrentMediaTime() }
    @objc func pickLevel(_ s: NSMenuItem) { levelIndex = s.tag; panel.level = levels[levelIndex].value; updateLabel(); log("level") }
    @objc func toggleFlag(_ s: NSMenuItem) {
        let f = flags[s.tag].value
        if behavior.contains(f) { behavior.remove(f) } else { behavior.insert(f) }
        rebuild()
    }
    @objc func pickMotion(_ s: NSMenuItem) { motion = Motion.allCases[s.tag]; rebuild() }
    @objc func pickScreen(_ s: NSMenuItem) { screenIndex = s.tag; rebuild() }
    @objc func quit() { NSApp.terminate(nil) }
}

func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let overlay = Overlay()
overlay.start()
app.run()
