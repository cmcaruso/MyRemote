/// The palette's App switcher: the Host holds ⌘ for the Remote, each tap sends Tab, and ⌘ comes up
/// (switching to the chosen app) once the taps have stopped for `idle` seconds.
public struct AppSwitcher: Sendable {
    public static let idle = 1.0

    /// When ⌘ should come up, in seconds on the caller's clock; nil while it isn't held.
    public private(set) var releaseAt: Double?

    public init() {}

    /// A tap at time `now`: ⌘ goes down if it isn't held yet, then Tab is pressed with it.
    public mutating func tap(at now: Double) -> [KeyEvent] {
        let first = releaseAt == nil
        releaseAt = now + Self.idle
        let tab = Keystrokes.press(Key.tab.code, flags: .command).filter { $0.code == Key.tab.code }
        return (first ? [Self.command(down: true)] : []) + tab
    }

    /// ⌘ up if it's held and due at `now`; nothing otherwise.
    public mutating func release(at now: Double) -> [KeyEvent] {
        guard let releaseAt, now >= releaseAt else { return [] }
        return releaseNow()
    }

    /// ⌘ up straight away if it's held, say because the Remote went away.
    public mutating func releaseNow() -> [KeyEvent] {
        guard releaseAt != nil else { return [] }
        releaseAt = nil
        return [Self.command(down: false)]
    }

    private static func command(down: Bool) -> KeyEvent {
        KeyEvent(code: 55, down: down, flags: down ? .command : [])
    }
}
