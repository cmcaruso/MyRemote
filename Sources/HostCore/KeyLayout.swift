/// Which key types a character in the Mac's keyboard layout, so a shortcut like ⌘Z presses the key
/// that says Z on this keyboard (on AZERTY that's where QWERTY has W).
public struct KeyLayout: Sendable {
    private var keys: [String: (code: UInt16, shift: Bool)] = [:]

    /// Keypad keys repeat the digits and some symbols; shortcuts want the main block's.
    private static let keypad: Set<UInt16> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    /// Builds the map by asking `translate` what each key types, without and then with Shift.
    /// The first key found for a character wins, unshifted before shifted.
    public init(translate: (_ code: UInt16, _ shift: Bool) -> String?) {
        for shift in [false, true] {
            for code in UInt16(0)..<128 where !Self.keypad.contains(code) {
                guard let typed = translate(code, shift), typed.count == 1,
                      typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
                      keys[typed] == nil else { continue }
                keys[typed] = (code, shift)
            }
        }
    }

    /// The key and flags for `character` with `flags` held: the character as it is, or lowercased if only
    /// that is on the keyboard. A character the layout lacks (⌘C on a Cyrillic layout) falls back to the
    /// US key, as macOS does for shortcuts.
    public func press(_ character: String, flags: KeyFlags) -> (code: UInt16, flags: KeyFlags)? {
        let lower = character.lowercased()
        guard let key = keys[character] ?? keys[lower] ?? Self.us.keys[character] ?? Self.us.keys[lower] else { return nil }
        return (key.code, key.shift ? flags.union(.shift) : flags)
    }

    /// The US ANSI layout.
    public static let us = KeyLayout { code, shift in
        let index = Int(code)
        let row = shift ? usShifted : usPlain
        guard index < row.count else { return nil }
        let character = row[index]
        return character == "\0" ? nil : String(character)
    }

    // What keycodes 0 through 50 type on a US keyboard; `\0` where there's no character key.
    private static let usPlain = Array("asdfhgzxcv\0bqweryt123465=97-80]ou[ip\0lj'k;\\,/nm.\0 `")
    private static let usShifted = Array("ASDFHGZXCV\0BQWERYT!@#$^%+(&_*)}OU{IP\0LJ\"K:|<?NM>\0 ~")
}
