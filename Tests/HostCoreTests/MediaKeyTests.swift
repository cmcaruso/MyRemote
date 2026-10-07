import HostCore
import Testing

@Suite("Media keys")
struct MediaKeyTests {
    /// data1 of a system-defined aux-control-button event: keytype << 16 | key state << 8,
    /// with keytypes from IOKit's ev_keymap.h and NX_KEYDOWN 10 / NX_KEYUP 11.
    @Test(arguments: [
        (MediaKey.playPause, 0x10_0A00, 0x10_0B00),
        (.next, 0x11_0A00, 0x11_0B00),
        (.previous, 0x12_0A00, 0x12_0B00),
        (.volumeUp, 0x00_0A00, 0x00_0B00),
        (.volumeDown, 0x01_0A00, 0x01_0B00),
        (.mute, 0x07_0A00, 0x07_0B00),
    ])
    func packsTheKeyAndItsStateLikeTheRealKey(_ key: MediaKey, _ down: Int, _ up: Int) {
        #expect(key.eventData(down: true) == down)
        #expect(key.eventData(down: false) == up)
    }
}
