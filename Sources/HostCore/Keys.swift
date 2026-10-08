/// A key the Remote names rather than types: the special-key bar, Return, Backspace and Space.
public enum Key: String, Sendable, CaseIterable {
    case escape = "esc"
    case tab
    case `return`
    case space
    case delete = "del"
    case forwardDelete = "fwddel"
    case left, right, up, down

    /// `kVK_*` from Carbon's `Events.h`.
    public var code: UInt16 {
        switch self {
        case .escape: 53
        case .tab: 48
        case .return: 36
        case .space: 49
        case .delete: 51
        case .forwardDelete: 117
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        }
    }

    /// Flags the real key carries on its own. Arrows sit on the numeric pad and the fn layer, forward
    /// delete on the fn layer; system shortcuts such as ⌃↑ (Mission Control) only match with them.
    public var ownFlags: KeyFlags {
        switch self {
        case .left, .right, .up, .down: [.numericPad, .function]
        case .forwardDelete: .function
        default: []
        }
    }
}

/// `CGEventFlags` bits a key event carries; the modifiers plus the two flags some keys bring along.
public struct KeyFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let shift = KeyFlags(rawValue: 0x20000)
    public static let control = KeyFlags(rawValue: 0x40000)
    public static let option = KeyFlags(rawValue: 0x80000)
    public static let command = KeyFlags(rawValue: 0x100000)
    public static let numericPad = KeyFlags(rawValue: 0x200000)
    public static let function = KeyFlags(rawValue: 0x800000)

    /// The modifiers in the order they go down; they come up in reverse.
    static let modifiers: [(flag: KeyFlags, code: UInt16, wire: String)] = [
        (.control, 59, "ctrl"),
        (.option, 58, "opt"),
        (.shift, 56, "shift"),
        (.command, 55, "cmd"),
    ]

    /// Modifiers named on the wire (`cmd`, `opt`, `ctrl`, `shift`); nil if any name is unknown.
    init?(wire names: [String]) {
        var flags: KeyFlags = []
        for name in names {
            guard let modifier = Self.modifiers.first(where: { $0.wire == name }) else { return nil }
            flags.insert(modifier.flag)
        }
        self = flags
    }
}

/// One key going down or up, as the Host posts it.
public struct KeyEvent: Equatable, Sendable {
    public var code: UInt16
    public var down: Bool
    public var flags: KeyFlags

    public init(code: UInt16, down: Bool, flags: KeyFlags = []) {
        self.code = code
        self.down = down
        self.flags = flags
    }

    /// A modifier key, which macOS posts as a flags-changed event rather than a key down or up.
    public var isModifier: Bool {
        KeyFlags.modifiers.contains { $0.code == code }
    }
}

public enum Keystrokes {
    /// The events for pressing key `code` with `flags`: each modifier key goes down first and comes up
    /// after, like fingers on a real keyboard, so apps that watch the modifier keys themselves see them.
    public static func press(_ code: UInt16, flags: KeyFlags = []) -> [KeyEvent] {
        let modifiers = KeyFlags.modifiers.filter { flags.contains($0.flag) }
        var held: KeyFlags = []
        var events: [KeyEvent] = []
        for modifier in modifiers {
            held.insert(modifier.flag)
            events.append(KeyEvent(code: modifier.code, down: true, flags: held))
        }
        events.append(KeyEvent(code: code, down: true, flags: flags))
        events.append(KeyEvent(code: code, down: false, flags: flags))
        for modifier in modifiers.reversed() {
            held.remove(modifier.flag)
            events.append(KeyEvent(code: modifier.code, down: false, flags: held))
        }
        return events
    }

    /// A named key with modifiers, plus the flags the key carries on its own.
    public static func press(_ key: Key, flags: KeyFlags = []) -> [KeyEvent] {
        press(key.code, flags: flags.union(key.ownFlags))
    }

    /// Splits text into the UTF-16 runs of Unicode-string key events, which carry at most `limit`
    /// units each. Runs break between characters, so an emoji or accented letter is never cut in two;
    /// a single character longer than the limit breaks between its scalars.
    public static func chunks(_ text: String, limit: Int = 20) -> [[UInt16]] {
        var runs: [[UInt16]] = []
        var run: [UInt16] = []
        func add(_ units: [UInt16]) {
            if run.count + units.count > limit, !run.isEmpty {
                runs.append(run)
                run = []
            }
            run += units
        }
        for character in text {
            let units = Array(character.utf16)
            if units.count <= limit {
                add(units)
            } else {
                for scalar in character.unicodeScalars { add(Array(String(scalar).utf16)) }
            }
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }
}
