import HostCore
import Testing

@Suite("Pressing keys")
struct KeystrokesTests {
    @Test func aPlainKeyGoesDownAndUp() {
        #expect(Keystrokes.press(Key.escape) == [
            KeyEvent(code: 53, down: true),
            KeyEvent(code: 53, down: false),
        ])
    }

    @Test func modifiersGoDownFirstAndComeUpInReverse() {
        // ⌘⇧Z: ⇧ then ⌘ down, each carrying the modifiers held so far.
        #expect(Keystrokes.press(6, flags: [.command, .shift]) == [
            KeyEvent(code: 56, down: true, flags: .shift),
            KeyEvent(code: 55, down: true, flags: [.shift, .command]),
            KeyEvent(code: 6, down: true, flags: [.shift, .command]),
            KeyEvent(code: 6, down: false, flags: [.shift, .command]),
            KeyEvent(code: 55, down: false, flags: .shift),
            KeyEvent(code: 56, down: false, flags: []),
        ])
    }

    @Test func arrowsCarryTheirOwnFlagsSoMissionControlMatches() {
        // ⌃↑ as the real keyboard sends it: the arrow on the numeric pad and fn layer.
        let events = Keystrokes.press(Key.up, flags: .control)
        #expect(events.map(\.code) == [59, 126, 126, 59])
        #expect(events[1].flags == [.control, .numericPad, .function])
        // The flags of the arrow stay on the arrow, not the modifier keys around it.
        #expect(events[0].flags == .control && events[3].flags == [])
        #expect(Keystrokes.press(Key.forwardDelete)[0].flags == .function)
    }

    @Test func shortTextIsOneRun() {
        #expect(Keystrokes.chunks("hello") == [Array("hello".utf16)])
        #expect(Keystrokes.chunks("") == [])
    }

    @Test func longTextSplitsIntoRunsOfTwentyUnits() {
        let text = String(repeating: "abcde", count: 9) // 45 units
        #expect(Keystrokes.chunks(text).map(\.count) == [20, 20, 5])
        #expect(Keystrokes.chunks(text).joined().elementsEqual(text.utf16))
    }

    @Test func runsNeverCutACharacter() {
        // 19 letters, then a 4-unit emoji with skin tone: the emoji moves to the next run whole.
        let text = String(repeating: "a", count: 19) + "👍🏽"
        #expect(Keystrokes.chunks(text) == [Array(repeating: 0x61, count: 19), Array("👍🏽".utf16)])
    }

    @Test func aCharacterLongerThanARunBreaksBetweenScalars() {
        // A family emoji: 7 scalars, 11 UTF-16 units. With a limit of 4, no surrogate pair is split.
        let family = "👨‍👩‍👧‍👦"
        let runs = Keystrokes.chunks(family, limit: 4)
        #expect(runs.joined().elementsEqual(family.utf16))
        #expect(runs.allSatisfy { $0.count <= 4 && String(utf16CodeUnits: $0, count: $0.count).utf16.count == $0.count })
        #expect(runs.allSatisfy { !UTF16.isLeadSurrogate($0.last!) })
    }
}

@Suite("Finding a character's key in the Mac's layout")
struct KeyLayoutTests {
    /// AZERTY's top letter row and a couple of shifted digits: Z and W swap with QWERTY, digits need Shift.
    static let azerty = KeyLayout { code, shift in
        let plain: [UInt16: String] = [0: "q", 6: "w", 12: "a", 13: "z", 18: "&", 46: ",", 49: " "]
        let shifted: [UInt16: String] = [0: "Q", 6: "W", 12: "A", 13: "Z", 18: "1", 46: "?"]
        return (shift ? shifted : plain)[code]
    }

    @Test func usesTheKeyThatSaysTheCharacterOnThisKeyboard() {
        #expect(Self.azerty.press("z", flags: .command)! == (13, .command))
        #expect(KeyLayout.us.press("z", flags: .command)! == (6, .command))
    }

    @Test func addsShiftWhenTheCharacterIsShifted() {
        #expect(Self.azerty.press("1", flags: .command)! == (18, [.command, .shift]))
        #expect(Self.azerty.press("?", flags: [])! == (46, .shift))
    }

    @Test func anUppercaseLetterIsTheShiftedKey() {
        #expect(Self.azerty.press("Z", flags: .command)! == (13, [.command, .shift]))
    }

    @Test func fallsBackToTheUSKeyForCharactersTheLayoutLacks() {
        let cyrillic = KeyLayout { code, shift in code == 8 ? (shift ? "С" : "с") : nil }
        #expect(cyrillic.press("c", flags: .command)! == (8, .command))
        #expect(cyrillic.press("v", flags: .command)! == (9, .command))
        #expect(cyrillic.press("€", flags: .command) == nil)
    }

    @Test func theUSLayoutCoversTheMainBlock() {
        let expected: [(String, UInt16, Bool)] = [
            ("a", 0, false), ("b", 11, false), ("q", 12, false), ("1", 18, false), ("0", 29, false),
            ("]", 30, false), ("p", 35, false), ("l", 37, false), ("\\", 42, false), ("/", 44, false),
            ("n", 45, false), (".", 47, false), (" ", 49, false), ("`", 50, false),
            ("B", 11, true), ("!", 18, true), ("?", 44, true), ("~", 50, true), ("\"", 39, true),
        ]
        for (character, code, shift) in expected {
            let press = KeyLayout.us.press(character, flags: [])
            #expect(press?.code == code, "\(character)")
            #expect(press?.flags == (shift ? .shift : []), "\(character)")
        }
    }

    @Test func prefersTheMainBlockOverTheKeypad() {
        let layout = KeyLayout { code, shift in
            !shift && (code == 83 || code == 18) ? "1" : nil
        }
        #expect(layout.press("1", flags: [])!.code == 18)
    }
}

@Suite("The App switcher")
struct AppSwitcherTests {
    @Test func theFirstTapHoldsCommandAndPressesTab() {
        var switcher = AppSwitcher()
        #expect(switcher.tap(at: 10) == [
            KeyEvent(code: 55, down: true, flags: .command),
            KeyEvent(code: 48, down: true, flags: .command),
            KeyEvent(code: 48, down: false, flags: .command),
        ])
        #expect(switcher.releaseAt == 11)
    }

    @Test func laterTapsOnlyPressTabAndPushTheReleaseBack() {
        var switcher = AppSwitcher()
        _ = switcher.tap(at: 10)
        #expect(switcher.tap(at: 10.6).map(\.code) == [48, 48])
        #expect(switcher.release(at: 11.2) == [])
        #expect(switcher.release(at: 11.6) == [KeyEvent(code: 55, down: false)])
        #expect(switcher.releaseAt == nil)
        #expect(switcher.release(at: 20) == [])
    }

    @Test func aTapAfterTheReleaseHoldsCommandAgain() {
        var switcher = AppSwitcher()
        _ = switcher.tap(at: 10)
        _ = switcher.release(at: 11)
        #expect(switcher.tap(at: 12).first == KeyEvent(code: 55, down: true, flags: .command))
    }

    @Test func releasingNowLetsGoAtOnceAndOnlyOnce() {
        var switcher = AppSwitcher()
        #expect(switcher.releaseNow() == [])
        _ = switcher.tap(at: 10)
        #expect(switcher.releaseNow() == [KeyEvent(code: 55, down: false)])
        #expect(switcher.releaseNow() == [])
    }
}

@Suite("Slide keys")
struct SlideKeyTests {
    @Test func pageDownAndUpComeFromTheFnLayerLikeAClicker() {
        #expect(Keystrokes.press(Key.pageDown) == [
            KeyEvent(code: 121, down: true, flags: .function),
            KeyEvent(code: 121, down: false, flags: .function),
        ])
        #expect(Keystrokes.press(Key.pageUp)[0] == KeyEvent(code: 116, down: true, flags: .function))
    }
}
