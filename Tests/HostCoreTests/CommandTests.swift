import HostCore
import Testing

@Suite("Decoding commands from the Remote")
struct CommandTests {
    @Test(arguments: [
        (#"{"t":"m","dx":1.5,"dy":-2}"#, Command.move(dx: 1.5, dy: -2)),
        (#"{"t":"c","b":0,"n":1}"#, .click(.left, count: 1)),
        (#"{"t":"c","b":0,"n":2}"#, .click(.left, count: 2)),
        (#"{"t":"c","b":1,"n":1}"#, .click(.right, count: 1)),
        (#"{"t":"d"}"#, .buttonDown),
        (#"{"t":"u"}"#, .buttonUp),
        (#"{"t":"s","dx":0,"dy":-12.5}"#, .scroll(dx: 0, dy: -12.5)),
        (#"{"t":"se","vx":0.1,"vy":-1.2}"#, .scrollEnd(vx: 0.1, vy: -1.2)),
        (#"{"t":"x"}"#, .touchDown),
        (#"{"t":"k","k":"play"}"#, .mediaKey(.playPause)),
        (#"{"t":"k","k":"next"}"#, .mediaKey(.next)),
        (#"{"t":"k","k":"prev"}"#, .mediaKey(.previous)),
        (#"{"t":"k","k":"volup"}"#, .mediaKey(.volumeUp)),
        (#"{"t":"k","k":"voldown"}"#, .mediaKey(.volumeDown)),
        (#"{"t":"k","k":"mute"}"#, .mediaKey(.mute)),
        (#"{"t":"v","v":0.4}"#, .setVolume(0.4)),
    ])
    func decodesEachCommand(_ text: String, _ expected: Command) {
        #expect(Command(decoding: text) == expected)
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"dx":1,"dy":1}"#,          // no type
        #"{"t":"zz","dx":1,"dy":1}"#, // unknown type
        #"{"t":"m","dx":1}"#,         // move without dy
        #"{"t":"m","dx":"1","dy":2}"#, // wrong field type
        #"{"t":"k","k":"eject"}"#,    // unknown media key
        #"{"t":"v"}"#,                // volume without a level
    ])
    func ignoresFramesItDoesNotUnderstand(_ text: String) {
        #expect(Command(decoding: text) == nil)
    }

    @Test(arguments: [(-0.2, 0.0), (1.7, 1.0), (0.0, 0.0), (1.0, 1.0)])
    func clampsTheVolumeToZeroThroughOne(_ sent: Double, _ expected: Double) {
        #expect(Command(decoding: #"{"t":"v","v":\#(sent)}"#) == .setVolume(expected))
    }
}
