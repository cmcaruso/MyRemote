# Input injection APIs on macOS 26 (ticket #4)

Question: which macOS APIs should the **Host** use to inject trackpad, keyboard, media and volume input on macOS 26, and what permissions do they need?

Researched 2026-10-07 against the macOS 26 SDK headers shipped with Xcode (`MacOSX.sdk`), Apple developer documentation / technotes, Apple DTS posts on the developer forums, and open-source implementations. Claims are tagged with a source number; see [Sources](#sources). Items marked **(verify in spike)** are well-supported by practice but not stated by Apple, and should be confirmed with a 10-minute test on the actual Mac.

## TL;DR

- **Everything except volume goes through one API family: Quartz Event Services (`CGEvent` + `CGEventPost`).** Pointer, clicks, drags, scroll, keys, and media keys are all `CGEvent`s posted to the HID tap.
- **One permission covers it all: System Settings > Privacy & Security > Accessibility.** Posting events is TCC service `PostEvent`, which System Settings shows under *Accessibility* [S1]. Input Monitoring is *not* needed (that's `ListenEvent`, only for event taps that read input) [S1]. Automation is not needed unless the Host sends Apple events to other apps (it shouldn't need to).
- **Volume: CoreAudio** (`AudioObjectSetPropertyData` with `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` on the default output device) for absolute "set to 40%"; **or the `NX_KEYTYPE_SOUND_UP/DOWN/MUTE` media-key event** for step changes with the native on-screen HUD. CoreAudio needs no permission and shows no HUD.
- **Code signing is the real gotcha:** TCC remembers the app by its code-signing *designated requirement*. An ad-hoc signed ("Sign to Run Locally") build has a DR pinned to its cdhash, so **every rebuild loses the Accessibility grant** [S2]. Sign every build with one stable identity (free Apple ID "Personal Team" Apple Development cert, or a self-signed code-signing cert in the login keychain) and keep the bundle ID fixed.
- **Don't sandbox the Host** (not required for PostEvent per DTS [S1], but simplest for a personal, non-App-Store app; and `AXIsProcessTrusted`-style Accessibility APIs are not sandbox-compatible [S1]).

## Per-capability API table

All `CGEvent*` APIs are in CoreGraphics (`CGEvent.h`, `CGEventTypes.h`, `CGEventSource.h`) [S3]. Swift names in parentheses.

| Capability | API | Key details | Permission |
|---|---|---|---|
| Move pointer | `CGEventCreateMouseEvent(src, kCGEventMouseMoved, pt, kCGMouseButtonLeft)` → `CGEventPost(kCGHIDEventTap, e)` (`CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`, `.post(tap: .cghidEventTap)`) | `pt` is in **global display coordinates**: origin at the top-left of the main display, y grows downward [S3, S4]. Remote sends deltas; Host computes `current + delta` and clamps to the union of `CGDisplayBounds()` over `CGGetActiveDisplayList()` (displays can be left/above main, so negative coords are valid). Read current position with `CGEventCreate(NULL)` → `CGEventGetLocation` (Swift: `CGEvent(source: nil)?.location`). Note `NSScreen`/AppKit uses bottom-left origin; don't mix. | Accessibility (PostEvent) |
| Move without events | `CGWarpMouseCursorPosition(pt)` | "Move the mouse cursor ... without generating events" [S3]. Apps won't see hover; prefer real `MouseMoved` events. Useful only for e.g. jumping the cursor to another display. | none needed for warp itself |
| Left / right / middle click | `kCGEventLeftMouseDown` + `kCGEventLeftMouseUp`; `kCGEventRightMouseDown/Up`; `kCGEventOtherMouseDown/Up` with button 2 | Post down then up at the *current* cursor position. `mouseButton` arg is only honoured for the `Other*` types [S3]. | Accessibility |
| Double / triple click | same as click, but set `kCGMouseEventClickState` = 1 on the first pair, 2 on the second pair (3 for triple) | Header: "A click state of 2 represents a double-click" [S3]. Apps decide double-click from this field, not from timing. KDE Connect's macOS remote-input backend does exactly this [S9]. | Accessibility |
| Drag | `LeftMouseDown` → series of `kCGEventLeftMouseDragged` at new positions → `LeftMouseUp` | Moving with a button down must use the `*Dragged` type, not `MouseMoved` [S9]. For a "tap-and-hold then move" gesture on the Remote, keep the Host in a "button held" state and emit `Dragged`. During a synthetic drag the system may suppress local hardware mouse events [S3, `CGEventSource.h`]. | Accessibility |
| Scroll (simple) | `CGEventCreateScrollWheelEvent2(src, kCGScrollEventUnitPixel, 2, dy, dx)` | Pixel units "produce an event that most applications interpret as a smooth scrolling event" [S3]. Line units ≈ 10 px/line by default and feel steppy [S3]. Wheel 1 = vertical, wheel 2 = horizontal. | Accessibility |
| Scroll (native trackpad feel) | as above, plus `CGEventSetIntegerValueField` for `kCGScrollWheelEventIsContinuous`(88)=1, `kCGScrollWheelEventScrollPhase`(99), `kCGScrollWheelEventMomentumPhase`(123), `kCGScrollWheelEventPointDeltaAxis1/2`(96/97), `kCGScrollWheelEventFixedPtDeltaAxis1/2`(93/94) | See [Scroll phases & momentum](#scroll-phases--momentum). | Accessibility |
| Text typing | `CGEventCreateKeyboardEvent(src, 0, true/false)` + `CGEventKeyboardSetUnicodeString(e, len, chars)` | Layout-independent; see [Unicode vs keycodes](#keyboard-unicode-vs-virtual-keycodes). Chunk ≤ 20 UTF-16 units per event [S10]. | Accessibility |
| Special keys & shortcuts | `CGEventCreateKeyboardEvent(src, kVK_*, down)` with `CGEventSetFlags(e, .maskCommand …)`; modifiers as separate `kVK_Command`/`kVK_Shift`… key events | Virtual keycodes are **physical positions** (`kVK_ANSI_A` = the key labelled A on a US layout) [S5]. `kVK_*` constants from Carbon `HIToolbox/Events.h` [S5]. | Accessibility |
| Media keys (play/pause, next, prev) | `NSEvent.otherEvent(with: .systemDefined, …, subtype: 8, data1: (key << 16) \| (down ? 0xA00 : 0xB00), data2: -1)` → `.cgEvent?.post(tap: .cghidEventTap)` with `key` = `NX_KEYTYPE_PLAY`(16) / `NX_KEYTYPE_NEXT`(17) / `NX_KEYTYPE_PREVIOUS`(18) (or `FAST`19 / `REWIND`20) | Subtype 8 = `NX_SUBTYPE_AUX_CONTROL_BUTTONS`; type `NX_SYSDEFINED`(14) [S6]. Post key-down then key-up. Same construction used by Hammerspoon [S7] and FnKeyboard [S8]. Not documented by Apple as a public API, but the constants are in public IOKit headers and this has been stable for 15+ years. | Accessibility |
| Volume up/down/mute (with HUD) | same media-key construction with `NX_KEYTYPE_SOUND_UP`(0) / `SOUND_DOWN`(1) / `MUTE`(7) | Behaves like the F11/F12 keys: native HUD, 1/16 steps, respects the user's "play feedback" setting (verify in spike). A DTS-thread poster confirms synthesized `NX_KEYTYPE_SOUND_UP` works [S11]. | Accessibility |
| Volume set absolute (no HUD) | CoreAudio: `AudioObjectGetPropertyData(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice)` → `AudioObjectSetPropertyData(dev, {kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain}, Float32 0…1)`; mute via `kAudioDevicePropertyMute` (UInt32) | `VirtualMainVolume` is "a Float32 … between 0.0 and 1.0 … maintains the relative balance between all the channels" [S12]. Hammerspoon's `hs.audiodevice` uses exactly this selector with `AudioObject*PropertyData` [S13]. Check `AudioObjectIsPropertySettable` first — HDMI/DisplayPort outputs often have no software volume. Listen with `AudioObjectAddPropertyListenerBlock` to push the current level to the Remote. | **none** |
| Brightness (optional) | `NX_KEYTYPE_BRIGHTNESS_UP`(2) / `_DOWN`(3) media-key events | Reported **not** to work when synthesized, while sound keys do [S11]. The working alternatives are private (`DisplayServices`) frameworks. Recommend: drop brightness from v1, or try the key event in the spike and keep it only if it works. | Accessibility |
| Permission check / prompt | `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` (macOS 10.15+); or `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | The `CGPreflight/RequestPostEventAccess` pair checks/requests exactly the "event synthesizing access" the Host needs [S3]. `AXIsProcessTrustedWithOptions` checks the broader Accessibility trust and can prompt asynchronously [S14]. Both land in the same Accessibility list in System Settings [S1]. | — |

### Which tap and which event source

- **Post to `kCGHIDEventTap`.** Events then enter "at the point where HID system events enter the window server" and pass through every later tap, so system-level handlers (Cmd+Tab switcher, Spotlight Cmd+Space, media-key routing) see them like real hardware input [S3]. Hammerspoon defaults to `kCGSessionEventTap` for keys [S7]; KDE Connect and FnKeyboard use the HID tap [S8, S9]. Use the HID tap for everything unless a spike shows a problem.
- **Use a private event source:** `CGEventSourceCreate(kCGEventSourceStatePrivate)`. The header says: "Very specialized applications such as **remote control programs** may want to generate and track event source state independent of other processes. These programs should use the `kCGEventSourceStatePrivate` value" [S3]. This keeps the Host's modifier state from mixing with whatever keys are physically held on the Mac.
- **Local-event suppression:** after a posted event, local hardware events *may* be suppressed for an interval (default 0.25 s) depending on the source's filter mask [S3]. Call `CGEventSourceSetLocalEventsSuppressionInterval(src, 0)` so the physical trackpad never feels "frozen" while the Remote is in use.

## Scroll phases & momentum

Plain pixel scroll events (`kCGScrollEventUnitPixel`, no phase) scroll smoothly in nearly every app, but don't trigger rubber-band overscroll, Safari's two-finger back/forward swipe, or the system's inertial momentum. To feel like a real trackpad, the Host has to emit the *phase* sequence a trackpad emits [S3, S15]:

Field numbers and enum values from `CGEventTypes.h` [S3]:

- `kCGScrollWheelEventScrollPhase` (99) uses `CGScrollPhase`: `Began=1`, `Changed=2`, `Ended=4`, `Cancelled=8`, `MayBegin=128`.
- `kCGScrollWheelEventMomentumPhase` (123) uses `CGMomentumScrollPhase`: `None=0`, `Begin=1`, `Continue=2`, `End=3`.
- `kCGScrollWheelEventIsContinuous` (88): "non-zero when the scrolling data is pixel-based".

Sequence used by Mac Mouse Fix's trackpad-scroll simulator [S15] (derived from observing real trackpad events):

1. `MayBegin`: first event, deltas 0 (finger down).
2. `Began`: first event with a non-zero delta.
3. `Changed`: every move in between (non-zero deltas).
4. `Ended`: finger lifted, deltas 0.
5. Momentum: events with scroll phase **0** and momentum phase `Begin` → `Continue`… → `End`, carrying the decaying deltas. The scroll phase and momentum phase are never both non-zero on one event.

Practical guidance for MyRemote:

- **v1:** pixel-unit scroll with `IsContinuous=1` plus the `Began/Changed/Ended` phases mapped 1:1 to touchstart/touchmove/touchend from the Remote. That alone gives correct smooth scrolling and lets apps tell "finger still down" from "finger lifted".
- **Momentum:** two options. (a) Have the Host generate the momentum tail itself after `Ended` (exponential decay from the last velocity, ~60–120 Hz, `MomentumPhase Begin/Continue/End`). This is what Mac Mouse Fix does, and it works reliably. (b) Send the momentum from the Remote (iOS Safari already computes it). (a) keeps the network quiet and latency-independent. Pick (a).
- Mac Mouse Fix notes that if you stop after `Ended` without a momentum `End`, some apps (Xcode) start their own "automatic momentum"; always close with a momentum `End` (or a tiny last delta) [S15].
- Safari page-swipe gestures additionally need private "type 29 / gesture" events [S15]. Out of scope; not worth it.
- Set both the integer point deltas (96/97) and the 16.16 fixed-point deltas (93/94); Mac Mouse Fix found the fixed-point ones are not always auto-filled on recent macOS [S15].

## Keyboard: Unicode vs virtual keycodes

Two different jobs, two different mechanisms:

**1. Typing text (Keyboard mode text field, dictation, emoji): use `CGEventKeyboardSetUnicodeString`.**

- It overrides the string the system would derive from the keycode + current layout [S3, S16], so `é`, `ß`, `€`, CJK and emoji arrive correctly **regardless of the Mac's keyboard layout** (Italian, US, etc.). Keycodes can't do this; they'd need dead-key sequences per layout.
- Create the event with keycode 0 (or any), then set the string, post key-down and key-up, and **clear flags** (`CGEventSetFlags(e, 0)`) so a held Shift/Cmd doesn't turn text into shortcuts. Hammerspoon does exactly this [S7].
- **Chunk to ≤ 20 UTF-16 code units per event**; longer strings are silently truncated [S10]. Never split a surrogate pair (emoji). KDE Connect sends one character per event [S9], which is simplest.
- Caveat from Apple: "application frameworks may ignore the Unicode string … and do their own translation based on the virtual keycode" [S3, S16]. In practice Cocoa/AppKit text views honour the string. Terminal emulators, games, remote-desktop/VM windows and some Electron apps may not (verify in spike). Fallback for ASCII: map char → keycode with `UCKeyTranslate` against `TISCopyCurrentKeyboardLayoutInputSource()`.

**2. Special keys and shortcuts (Return, Esc, arrows, Delete, Cmd+Tab, Cmd+Space, Cmd+C…): use virtual keycodes.**

- `kVK_*` are layout-independent *positions*. "Other keyboard layouts may have the 'A' key label on a different physical key" [S5]. Non-letter keys (`kVK_Return`, `kVK_Tab`=0x30, `kVK_Space`=0x31, `kVK_Command`=0x37, arrows, F-keys) are safe on any layout.
- For letter shortcuts on non-US layouts (e.g. Cmd+Z on a QWERTZ/AZERTY Mac), macOS matches most menu shortcuts by **character**, so pick the keycode that produces that character on the current layout (via `UCKeyTranslate`) rather than hard-coding `kVK_ANSI_Z`. For Italian QWERTY the letters are in US positions, so this matters little for this user, but it's cheap to do right.
- Modifier combos: send the modifier key-down (`kVK_Command`) as its own event, then the key down/up **with `CGEventSetFlags(.maskCommand)` set on them**, then the modifier key-up. Apple's header shows the same pattern for Shift+Z [S3]. KDE Connect posts modifiers as separate events the same way [S9].
- **Cmd+Tab:** the app switcher stays open while Cmd is held. Model it as a "hold Cmd" toggle on the Remote: Cmd down → Tab down/up (repeat to cycle) → Cmd up to commit. Post at `kCGHIDEventTap` (verify in spike).
- **Cmd+Space** (Spotlight) and other system hotkeys: work as normal keycode + flags at the HID tap (verify in spike).

## Media keys and where they land

- The `NX_SYSDEFINED` / subtype 8 event is the same event a physical keyboard's F7–F9 keys generate [S6]. macOS routes it through the system "Now Playing" mechanism, not to the frontmost app: apps that register with `MPRemoteCommandCenter` (available on macOS since 10.12.2) receive play/pause/next/previous [S17].
- **Music** and **Spotify** register as Now Playing apps; **Safari and Chrome** forward to web pages via the Media Session API (Chromium's `system_media_controls/mac` bridge to `MPRemoteCommandCenter` [S18]). So a synthesized play/pause hits *whichever app most recently became Now Playing*, the same as the hardware key (verify in spike with Spotify + YouTube in a browser).
- Gotcha: if nothing is Now Playing, macOS launches Music on play/pause (same as the hardware key).
- Showing what's playing on the Remote would need the private `MediaRemote` framework, which was further locked down in recent macOS. Out of scope for this ticket.

## Volume: recommendation

| Approach | HUD | Absolute level | Permission | Notes |
|---|---|---|---|---|
| `NX_KEYTYPE_SOUND_*` media-key event | yes (native) | no (steps) | Accessibility (already have) | Exactly like the keyboard keys. Mute toggles. |
| CoreAudio `VirtualMainVolume` | no | yes, 0.0–1.0 | none | Can read the level back and observe changes. Fails on devices without software volume (check settable). |
| AppleScript `set volume output volume N` via `NSAppleScript`/`osascript` | no | yes | none for this command (Standard Additions, not an Apple event to another app) | Slower, spawns script machinery. No advantage over CoreAudio. |

**Use both:** media-key events for the Remote's +/−/mute buttons (native HUD, familiar steps), and CoreAudio for a slider/absolute set plus for reading the current level to show on the Remote. Skip AppleScript.

## Permissions (TCC) in detail

From Apple DTS (Quinn) [S1]:

> there are three TCC privileges involved:
> - `PostEvent`: controls the ability to post UI events, for example, by calling the `CGEvent.post(tap:)` method
> - `ListenEvent`: controls the ability to monitor UI events on a system-wide basis, for example, with a CG event tap.
> - `Accessibility`: aimed at accessibility products … including the ability to examine the UI state of other apps.
>
> Both `PostEvent` and `Accessibility` map to Accessibility [in System Settings]. `ListenEvent` maps to Input Monitoring.

Mapping for MyRemote:

| Need | TCC service | System Settings pane | Needed? |
|---|---|---|---|
| Post mouse/keyboard/media events (`CGEventPost`) | PostEvent | Accessibility | **Yes** |
| Read other apps' UI (AXUIElement) | Accessibility | Accessibility | No (not planned) |
| Watch global input (event tap) | ListenEvent | Input Monitoring | No (Host only injects) |
| Send Apple events to other apps | AppleEvents | Automation | No |
| CoreAudio volume | (none) | — | No |
| Laser overlay window (Presentation mode) | (none; drawing a window doesn't need Screen Recording) | — | No |

Notes:

- `IOHIDPostEvent` (older IOKit route) is gated by the same post-event access (`kIOHIDRequestTypePostEvent`) [S19]; no reason to use it over `CGEventPost`.
- If the grant is missing, `CGEventPost` silently drops events (no error return; `CGEventPost` is `void` [S3]). So the Host **must** call `CGPreflightPostEventAccess()` at launch and show a "Grant Accessibility" state in the menubar, calling `CGRequestPostEventAccess()` (opens the prompt/System Settings) when the user clicks it.
- Revoking the grant while running: a recent DTS thread (repro on Sequoia and Tahoe) shows WindowServer re-checking `kTCCServicePostEvent`/`kTCCServiceListenEvent` when the record changes [S20]. That bug is about active *event taps*; the Host has none, but it should re-check access periodically or on failure rather than assume it once at launch.

## Code signing and rebuilds

How TCC recognises "the same app" (TN3127 [S2]):

> macOS solves this problem by recording your app's DR [designated requirement] in its database … Each time your app tries to access [the resource], macOS checks that this version of the app satisfies the original DR.
>
> Unsigned code has no DR. Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code. … If you tweak the code and run it again, macOS repeats that prompt.

Checked locally on this Mac: an ad-hoc signed binary's DR is literally `designated => cdhash H"…"`, so any code change creates a new DR. `security find-identity -v -p codesigning` currently reports **0 valid identities** on this Mac, so builds today would be ad-hoc.

Implications and options for a personal app:

1. **Ad-hoc ("Sign to Run Locally"):** works, but every rebuild needs Accessibility re-granted. In practice the old entry stays in the list but no longer matches: toggle it off/on or remove and re-add, or `tccutil reset Accessibility <bundle-id>` then re-grant. Fine for the first spike, painful afterwards.
2. **Free Apple ID "Personal Team" in Xcode (Apple Development certificate):** DR becomes `identifier "<bundle id>" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" and …` [S2], which is stable across rebuilds. DTS recommends Apple Development signing for exactly this reason, to "radically cut down on the amount of TCC thrash" [S21]. Recommended: zero cost, Xcode manages it. The cert expires yearly (renewal changes the leaf but the DR keys on the CN/issuer, so the grant should survive; verify on renewal).
3. **Self-signed code-signing certificate** (Keychain Access > Certificate Assistant > Create a Certificate, type "Code Signing", or `openssl` + `security import`): DR pins the leaf certificate hash, which is stable as long as the same cert is used. Reported to keep the Accessibility grant across rebuilds [S22]. Make it long-lived (e.g. 10 years), since replacing the cert resets the grant.
4. Whatever the identity: **keep the bundle identifier fixed**, run the app from one stable path (e.g. `/Applications/MyRemote Host.app`), and don't alternate between Debug-from-Xcode and Release-from-Applications builds signed differently.
5. **Hardened runtime / notarization:** not needed for a locally built app. No entitlement is required for `CGEventPost`. **Don't enable App Sandbox**: PostEvent works in the sandbox per DTS [S1], but sandboxing adds network-server entitlements and friction for no benefit here.

## Open items to confirm in the first Host spike

1. Cmd+Tab hold-and-cycle and Cmd+Space via HID tap.
2. Media play/pause reaches Spotify and a YouTube tab in Safari/Chrome.
3. `NX_KEYTYPE_SOUND_*` shows the HUD on macOS 26.6; brightness keys do or don't work.
4. Unicode typing into Terminal and one Electron app.
5. Phase-tagged scroll + Host-generated momentum feels native in Safari, Finder, Xcode.

## Sources

- **[S1]** Apple DTS (Quinn), "Clipboard manager rejected under Guideline 2.4.5 for using CGEvent.post", Apple Developer Forums: https://developer.apple.com/forums/thread/820594. Also related: https://developer.apple.com/forums/thread/780626
- **[S2]** Apple, TN3127: Inside Code Signing: Requirements: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- **[S3]** macOS 26 SDK headers, `CoreGraphics.framework/Headers/CGEvent.h`, `CGEventTypes.h`, `CGEventSource.h`, `CGRemoteOperation.h` (Xcode `MacOSX.sdk`). Online: https://developer.apple.com/documentation/coregraphics/quartz-event-services
- **[S4]** Apple, `CGDisplayBounds(_:)`: "expressed as a rectangle in the global display coordinate space (relative to the upper-left corner of the main display)": https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)
- **[S5]** macOS 26 SDK, `Carbon.framework/…/HIToolbox.framework/Headers/Events.h` (`kVK_*` virtual keycodes and their layout note)
- **[S6]** macOS 26 SDK, `IOKit.framework/Headers/hidsystem/ev_keymap.h` (`NX_KEYTYPE_*`) and `IOLLEvent.h` (`NX_SYSDEFINED`, `NX_SUBTYPE_AUX_CONTROL_BUTTONS = 8`)
- **[S7]** Hammerspoon, `extensions/eventtap/libeventtap_event.m` (system-key, scroll, and Unicode key event construction): https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap_event.m
- **[S8]** FnKeyboard, `Sources/KeySimulator.swift` (Swift media/volume key events posted to `.cghidEventTap`): https://github.com/kotique123/FnKeyboard/blob/main/Sources/KeySimulator.swift
- **[S9]** KDE Connect, `plugins/mousepad/macosremoteinput.mm` (phone-to-Mac remote input: moves, clicks, double-click via click state, drag, pixel scroll, Unicode typing, `AXIsProcessTrustedWithOptions`): https://invent.kde.org/network/kdeconnect-kde/-/blob/master/plugins/mousepad/macosremoteinput.mm
- **[S10]** "CGEventKeyboardSetUnicodeString will only process up to 20 characters", Qt Forum: https://forum.qt.io/post/46576 ; KDE Connect MR "Fix and improve unicode input on macOS and Windows": https://invent.kde.org/network/kdeconnect-kde/-/merge_requests/467
- **[S11]** "NX_KEYTYPE_BRIGHTNESS_UP/DOWN doesn't work" (sound keys work when synthesized; brightness doesn't), Apple Developer Forums: https://developer.apple.com/forums/thread/60545
- **[S12]** macOS 26 SDK, `AudioToolbox.framework/Headers/AudioHardwareService.h` (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`) and `CoreAudio.framework/Headers/AudioHardware.h` (`kAudioHardwarePropertyDefaultOutputDevice`, `kAudioDevicePropertyVolumeScalar`, `kAudioDevicePropertyMute`)
- **[S13]** Hammerspoon, `extensions/audiodevice/libaudiodevice.m` (`AudioObjectGet/SetPropertyData` with `VirtualMainVolume`): https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/audiodevice/libaudiodevice.m
- **[S14]** Apple, `AXIsProcessTrustedWithOptions`: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- **[S15]** Mac Mouse Fix, `Helper/Core/Touch/GestureScrollSimulator.m` (trackpad-like scroll phases, momentum, field numbers): https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/GestureScrollSimulator.m
- **[S16]** Apple, `CGEvent.keyboardSetUnicodeString(stringLength:unicodeString:)`: https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)
- **[S17]** Apple, `MPRemoteCommandCenter` (macOS 10.12.2+): https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
- **[S18]** Chromium, `components/system_media_controls/mac/`: https://chromium.googlesource.com/chromium/src/+/main/components/system_media_controls/mac/
- **[S19]** macOS 26 SDK, `IOKit.framework/Headers/hidsystem/IOHIDLib.h` (`IOHIDCheckAccess` / `IOHIDRequestAccess`, `kIOHIDRequestTypePostEvent`)
- **[S20]** "System input becomes unresponsive when Accessibility permission is revoked while a CGEventTap is active", Apple Developer Forums: https://developer.apple.com/forums/thread/844416
- **[S21]** Apple DTS (Quinn), "How to handle TCC permissions on m…", Apple Developer Forums: https://developer.apple.com/forums/thread/730043
- **[S22]** sunfmin, "macos-codesign" skill (self-signed cert keeps Accessibility across rebuilds; ad-hoc pins to cdhash): https://www.skills.sh/sunfmin/macos-codesign-skill/macos-codesign. Secondary source, consistent with TN3127.
