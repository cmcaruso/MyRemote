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
        (#"{"t":"tx","bs":2,"s":"lo"}"#, .type(backspaces: 2, text: "lo")),
        (#"{"t":"tx","bs":0,"s":"é👍🏽"}"#, .type(backspaces: 0, text: "é👍🏽")),
        (#"{"t":"kp","k":"left"}"#, .key(.left, [])),
        (#"{"t":"kp","k":"up","m":["ctrl"]}"#, .key(.up, .control)),
        (#"{"t":"kp","k":"del","m":["opt"]}"#, .key(.delete, .option)),
        (#"{"t":"kp","c":"z","m":["cmd","shift"]}"#, .character("z", [.command, .shift])),
        (#"{"t":"kp","c":" ","m":["cmd"]}"#, .character(" ", .command)),
        (#"{"t":"as"}"#, .appSwitcher),
        (#"{"t":"kp","k":"pgdn"}"#, .key(.pageDown, [])),
        (#"{"t":"kp","k":"pgup"}"#, .key(.pageUp, [])),
        (#"{"t":"ls"}"#, .laserStart),
        (#"{"t":"l","dx":3,"dy":-1.5}"#, .laserMove(dx: 3, dy: -1.5)),
        (#"{"t":"le"}"#, .laserEnd),
        (#"{"t":"g","g":"pinch","d":0.04}"#, .gesture(.pinch, delta: 0.04)),
        (#"{"t":"g","g":"rotate","d":-12.5}"#, .gesture(.rotate, delta: -12.5)),
        (#"{"t":"g","g":"spaces","d":-0.3}"#, .gesture(.spaces, delta: -0.3)),
        (#"{"t":"ge","g":"pinch","ok":true}"#, .gestureEnd(.pinch, completes: true)),
        (#"{"t":"ge","g":"missionControl","ok":false}"#, .gestureEnd(.missionControl, completes: false)),
        (#"{"t":"ga","a":"smartZoom"}"#, .gestureAction(.smartZoom)),
        (#"{"t":"ga","a":"pageBack"}"#, .gestureAction(.pageBack)),
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
        #"{"t":"tx","bs":-1,"s":""}"#, // negative backspaces
        #"{"t":"tx","s":"a"}"#,       // typing without a backspace count
        #"{"t":"kp","k":"f13"}"#,     // unknown key
        #"{"t":"kp","c":"ab"}"#,      // more than one character
        #"{"t":"kp","k":"tab","c":"a"}"#, // both a key and a character
        #"{"t":"kp","m":["cmd"]}"#,   // neither
        #"{"t":"kp","c":"a","m":["hyper"]}"#, // unknown modifier
        #"{"t":"l","dx":3}"#,         // Laser move without dy
        #"{"t":"g","g":"swirl","d":1}"#, // unknown Gesture
        #"{"t":"g","g":"pinch"}"#,    // Gesture without a delta
        #"{"t":"ge","g":"pinch"}"#,   // end without ok
        #"{"t":"ga","a":"undo"}"#,    // unknown action
    ])
    func ignoresFramesItDoesNotUnderstand(_ text: String) {
        #expect(Command(decoding: text) == nil)
    }

    @Test(arguments: [(-0.2, 0.0), (1.7, 1.0), (0.0, 0.0), (1.0, 1.0)])
    func clampsTheVolumeToZeroThroughOne(_ sent: Double, _ expected: Double) {
        #expect(Command(decoding: #"{"t":"v","v":\#(sent)}"#) == .setVolume(expected))
    }
}
