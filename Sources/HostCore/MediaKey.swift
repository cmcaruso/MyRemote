/// A key from the Mac keyboard's media row, posted as a system-defined event like the real key.
public enum MediaKey: String, Sendable, CaseIterable {
    case playPause = "play"
    case next
    case previous = "prev"
    case volumeUp = "volup"
    case volumeDown = "voldown"
    case mute
}

extension MediaKey {
    /// `NX_KEYTYPE_*` from IOKit's `ev_keymap.h`.
    var keyType: Int {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// `data1` of the system-defined event (subtype 8, `NX_SUBTYPE_AUX_CONTROL_BUTTONS`) for this key
    /// going down or up: the keytype in the high 16 bits, `NX_KEYDOWN` (10) or `NX_KEYUP` (11) above the low byte.
    public func eventData(down: Bool) -> Int {
        keyType << 16 | (down ? 0xA : 0xB) << 8
    }
}
