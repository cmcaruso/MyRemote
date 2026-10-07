import HostCore
import Testing

@Suite("Decoding commands from the Remote")
struct CommandTests {
    @Test func decodesAPointerMove() {
        #expect(Command(decoding: #"{"t":"m","dx":1.5,"dy":-2}"#) == .move(dx: 1.5, dy: -2))
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"dx":1,"dy":1}"#,          // no type
        #"{"t":"zz","dx":1,"dy":1}"#, // unknown type
        #"{"t":"m","dx":1}"#,         // move without dy
        #"{"t":"m","dx":"1","dy":2}"#, // wrong field type
    ])
    func ignoresFramesItDoesNotUnderstand(_ text: String) {
        #expect(Command(decoding: text) == nil)
    }
}
