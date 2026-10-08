# Trackpad gesture settings: where macOS keeps them, and how the Host can read and watch them

Research for [#43](https://github.com/cmcaruso/MyRemote/issues/43). Checked on macOS 26.6 (Tahoe), build 25G83, on a MacBook with a built-in trackpad and a Magic Trackpad paired.

## Answer

- **The source of truth is the `com.apple.AppleMultitouchTrackpad` domain.** On macOS 26 the built-in trackpad and the Magic Trackpad both report `ApplePreferenceIdentifier = "com.apple.AppleMultitouchTrackpad"` in the IORegistry. The older `com.apple.driver.AppleBluetoothMultitouch.trackpad` domain still exists and is mostly mirrored, but it can be stale. On the test Mac it had `TrackpadThreeFingerVertSwipeGesture = 1` while the live value was `2`.
- A few settings live elsewhere:
  - Natural scrolling, two-finger page swipe and Force Click look-up are in the global domain (`NSGlobalDomain`).
  - The on/off switches for Mission Control, App Exposé, Launchpad and Show Desktop are in `com.apple.dock`.
  - Settings also writes a mirror of most trackpad keys to the global domain for the current host (`defaults -currentHost read -g`, keys `com.apple.trackpad.*`).
- **Reading works with the plain APIs.** `UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")`, `UserDefaults(suiteName: "com.apple.dock")` and `UserDefaults.standard` (for global keys) all return the live values. So does `CFPreferencesCopyAppValue` / `CFPreferencesCopyValue(..., kCFPreferencesCurrentHost)`. The Host is unsandboxed, so it needs no entitlement or permission prompt.
- **Watching works too, but by different means for different domains** (all tested; details below):
  - For `com.apple.AppleMultitouchTrackpad` and `com.apple.dock`, use **KVO on a `UserDefaults(suiteName:)` instance**. It fired within about 10 ms when the setting was flipped in System Settings.
  - For global keys, KVO did **not** fire. Instead, Settings posts named **distributed notifications** such as `SwipeScrollDirectionDidChangeNotification`. Every trackpad-domain change was also followed by `com.apple.IOTrackpadPropertyDidChangeNotification`.
  - A cheap catch-all is to re-read everything when any of these signals arrives, and on each Remote (re)connect.

## Settings → keys

**Domain abbreviations:**
- **TP** = `com.apple.AppleMultitouchTrackpad`
- **BT** = `com.apple.driver.AppleBluetoothMultitouch.trackpad` (legacy mirror, same key names)
- **G** = `NSGlobalDomain` (`defaults read -g`)
- **G/host** = `NSGlobalDomain` for the current host (`defaults -currentHost read -g`)
- **Dock** = `com.apple.dock`

**What the confidence labels mean:**
- **Verified**: the value was read with `defaults` while System Settings showed the matching UI label. The Settings UI was read through the Accessibility API, without clicking anything except tabs.
- **Verified live**: the setting was flipped in System Settings while a watcher was running, then flipped back.
- **Inferred**: taken from key names, enum names in the Settings binaries, and the driver's default-preferences dictionary, but no specific value was observed for that UI option.

Where a key is missing, use the driver default. The driver publishes its defaults as `ApplePreferencesDefaultPreferences` on the `AppleMultitouchTrackpadHIDEventDriver` IORegistry entry (`ioreg -r -c AppleMultitouchTrackpadHIDEventDriver -l -d 1`). For example, `Clicking = 0` there.

### Point & Click tab

| Setting (UI label) | Domain · key | Encoding | Confidence |
|---|---|---|---|
| Tap to click | TP `Clicking` (bool). Mirror: G/host `com.apple.mouse.tapBehavior` (int, 1 = on) | 1 = on, 0 = off | Verified (1 ↔ on) |
| Secondary click: "Click or Tap with Two Fingers" | TP `TrackpadRightClick` = 1, `TrackpadCornerSecondaryClick` = 0. Mirror: G/host `com.apple.trackpad.enableSecondaryClick` | — | Verified |
| Secondary click: "Click in Bottom Right / Bottom Left Corner" | TP `TrackpadCornerSecondaryClick` (int) with `TrackpadRightClick` = 0. Mirror: G/host `com.apple.trackpad.trackpadCornerClickBehavior` | 2 = bottom right, 1 = bottom left, 0 = none | Inferred |
| Look up & data detectors: "Force Click with One Finger" | G `com.apple.trackpad.forceClick` = 1 and TP `TrackpadThreeFingerTapGesture` = 0 | — | Verified |
| Look up & data detectors: "Tap with Three Fingers" | TP `TrackpadThreeFingerTapGesture` = 2 (mirror: G/host `com.apple.trackpad.threeFingerTapGesture`) | 2 = on, 0 = off | Inferred |
| Look up & data detectors: Off | TP `TrackpadThreeFingerTapGesture` = 0 and G `com.apple.trackpad.forceClick` = 0 | — | Inferred |
| Force Click and haptic feedback | TP `ForceSuppressed` (bool, inverted) | 0 = Force Click on | Verified |
| Quiet Click / click pressure | TP `ActuationStrength` (0 = quiet), `FirstClickThreshold` / `SecondClickThreshold` (0 light, 1 medium, 2 firm) | — | Partly verified (Quiet Click on ↔ `ActuationStrength` = 0) |

### Accessibility → Pointer Control → Trackpad Options (dragging)

Three-finger drag has been in Accessibility, not the Trackpad pane, since OS X El Capitan. See Apple's [Turn on three-finger drag](https://support.apple.com/en-us/102341). The keys did **not** move: the Accessibility pane (`AccessibilitySettingsExtension`, strings `pointerControl.trackpadOptions.draggingStyle.{withoutLock,withLock,threeFinger}`, `setThreeFingerDrag:`) still writes the same trackpad keys. `com.apple.universalaccess` has no dragging key.

| "Use trackpad for dragging" + Dragging style | TP keys | Confidence |
|---|---|---|
| Off | `Dragging` = 0, `DragLock` = 0, `TrackpadThreeFingerDrag` = 0 | Verified (current state) |
| Without Drag Lock | `Dragging` = 1, `DragLock` = 0 | Inferred |
| With Drag Lock | `Dragging` = 1, `DragLock` = 1 | Inferred |
| Three Finger Drag | `TrackpadThreeFingerDrag` = 1 (mirror: G/host `com.apple.trackpad.threeFingerDragGesture`) | Inferred |

When three-finger drag is on, three fingers are taken, so macOS moves the three-finger swipes to four fingers. Expect `TrackpadThreeFinger{Horiz,Vert}SwipeGesture` to become 0, with the four-finger keys carrying the gesture. This is inferred from Apple's gesture page ("in some versions … three fingers instead of four") and the pane's behaviour. Have the Remote check `TrackpadThreeFingerDrag` first.

### Scroll & Zoom tab

| Setting | Domain · key | Encoding | Confidence |
|---|---|---|---|
| Natural scrolling | G `com.apple.swipescrolldirection` (bool) | 1 = natural | **Verified live** (Settings flips it and posts `SwipeScrollDirectionDidChangeNotification`) |
| Zoom in or out (pinch) | TP `TrackpadPinch` (mirror: G/host `com.apple.trackpad.pinchGesture`) | 1 = on | Verified |
| Smart zoom | TP `TrackpadTwoFingerDoubleTapGesture` (mirror: G/host `com.apple.trackpad.twoFingerDoubleTapGesture`) | 1 = on, 0 = off | Verified |
| Rotate | TP `TrackpadRotate` (mirror: G/host `com.apple.trackpad.rotateGesture`) | 1 = on, 0 = off | **Verified live** |

Other scroll keys: `TrackpadScroll`, `TrackpadHorizScroll` and `TrackpadMomentumScroll` (bools, on by default). Scrolling itself can be turned off in Accessibility.

### More Gestures tab

| Setting | Domain · key | Encoding | Confidence |
|---|---|---|---|
| Swipe between pages | G `AppleEnableSwipeNavigateWithScrolls` (bool) **and** TP `TrackpadThreeFingerHorizSwipeGesture` | "Scroll Left or Right with Two Fingers" = G 1 + TP 3F-horiz ≠ 1 (verified). "Swipe with Three Fingers" = G 0 + 3F-horiz = 1. "Swipe with Two or Three Fingers" = G 1 + 3F-horiz = 1. Off = G 0 + 3F-horiz ≠ 1 | Two-finger verified, rest inferred |
| Swipe between full-screen applications | TP `TrackpadThreeFingerHorizSwipeGesture` and `TrackpadFourFingerHorizSwipeGesture` | 3F-horiz = 2 → three fingers (verified: 3F = 2, 4F = 2 showed "Swipe Left or Right with Three Fingers"). 3F-horiz ≠ 2 and 4F-horiz = 2 → four fingers. Both ≠ 2 → off | Three fingers verified, rest inferred |
| Notification Center | TP `TrackpadTwoFingerFromRightEdgeSwipeGesture` (mirror: G/host `com.apple.trackpad.twoFingerFromRightEdgeSwipeGesture`) | 3 = on, 0 = off | Verified (3 ↔ on) |
| Mission Control | TP `TrackpadThreeFingerVertSwipeGesture` / `TrackpadFourFingerVertSwipeGesture`; Dock `showMissionControlGestureEnabled` (bool, missing = on) | Same 3F/4F rule as full-screen apps, with value 2 = Mission Control. Off = Dock bool 0 | Three fingers verified (3F = 2, 4F = 2, Dock key missing), off inferred |
| App Exposé | Same vertical-swipe keys (swipe down); Dock `showAppExposeGestureEnabled` (bool) | On + three fingers verified (Dock = 1, 3F-vert = 2). Off = Dock 0 | Partly verified |
| Show Desktop | TP `TrackpadFourFingerPinchGesture` / `TrackpadFiveFingerPinchGesture` (2 = on); Dock `showDesktopGestureEnabled` (bool, missing = on) | — | On verified (pinch keys 2, Dock key missing), off inferred |
| Launchpad | Same pinch keys; Dock `showLaunchpadGestureEnabled` | — | **No longer in the macOS 26 Trackpad pane.** The More Gestures tab shows only Swipe between pages, Swipe between full-screen applications, Notification Center, Mission Control, App Exposé and Show Desktop. Apple's [gesture page](https://support.apple.com/en-us/102482) now calls the thumb-and-three-finger pinch "Apps". The keys remain; treat "pinch" as always on unless the Dock bool is 0. |

Value `2` on the swipe/pinch keys means "system gesture enabled". The full-screen-apps and Mission Control rows are the two that need care. Per the Settings binary's video names (`SwipeBetweenFullScreen-3F/-4F`, `SwipeBetweenPages-2F/-3F`), the pane models a single 3-or-4-finger choice. On disk, though, the four-finger key stays at 2 even when three fingers is chosen. So decide from the **three-finger** key: value 2 → three fingers, value 1 (pages) or 0 → four fingers, provided the four-finger key is 2.

## Reading from the Host

All of the following were run as an ordinary unsandboxed Swift process (`swift script.swift`) on the test Mac:

```swift
let tp   = UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")!
let dock = UserDefaults(suiteName: "com.apple.dock")!
tp.object(forKey: "TrackpadThreeFingerDrag")                     // → 0
dock.object(forKey: "showMissionControlGestureEnabled")          // → nil (missing ⇒ default on)
UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection")       // global key → 1
UserDefaults.standard.object(forKey: "com.apple.trackpad.threeFingerHorizSwipeGesture") // current-host global is in the search list → 2
CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) // also works
```

- `UserDefaults(suiteName: "NSGlobalDomain")` returns nil and logs "does not make sense". Read global keys through `UserDefaults.standard`. ([init(suiteName:)](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)) says not to pass the global domain.)
- Use `object(forKey:)`, not `bool`/`integer`, so that "missing" (fall back to the driver default) can be told apart from 0.
- The live values the driver is using also appear in `IOHIDSystem`'s `HIDParameters` (`ioreg -r -c IOHIDSystem -l -d 1`). They matched TP, not the stale BT domain. This is a useful cross-check but not needed.

## Watching for changes

Apple documents that `UserDefaults.didChangeNotification` fires only for changes made **in the current process**. For changes made by another process, Apple says: "register a key-value observer on the UserDefaults object. Key-value observing reports all updates to setting values, regardless of which process made the change." ([didChangeNotification](https://developer.apple.com/documentation/foundation/userdefaults/didchangenotification))

Results on macOS 26.6:

| Mechanism | Result |
|---|---|
| KVO on `UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")`, key `TrackpadRotate`, while flipping Rotate in System Settings | **Fired** about 10 ms after the change, both directions |
| KVO on a suite for a scratch domain written by `defaults write` from another process (any-host and `-currentHost`) | Fired, including on delete (new value `<null>`) |
| KVO on `UserDefaults.standard` for keys in the global domain (any-host or current-host), written by another process | **Did not fire**, although a fresh read returned the new value |
| `UserDefaults.didChangeNotification` for another process's write | Did not fire (as documented) |
| `DistributedNotificationCenter` observer with `name: nil` (wildcard) | Received **nothing** from other processes, not even a test post, while a named observer got it. Wildcard sniffing is not available to a normal user process, so names must be known in advance |
| Named distributed notification `com.apple.IOTrackpadPropertyDidChangeNotification` | Posted by Settings on every Rotate change (no `userInfo`) |
| Named distributed notification `SwipeScrollDirectionDidChangeNotification` | Posted by Settings on every Natural scrolling change (no `userInfo`) |
| `DispatchSource` vnode watch on `~/Library/Preferences` | Fires on writes, but `cfprefsd` writes plists lazily and atomically, so this is noisy and late. Not recommended |

Other notification names compiled into the Trackpad settings extension, which are likely posted for the matching settings. These were **not observed** because only Rotate and Natural scrolling were toggled:
- `AppleEnableSwipeNavigateWithScrollsDidChangeNotification`
- `3FHorizSwipeDidChangeNotification`, `3FVertSwipeDidChangeNotification`, `4FHorizSwipeDidChangeNotification`, `4FVertSwipeDidChangeNotification`
- `TapBehaviorDidChangeNotification`
- `com.apple.ForceSuppressedDidChangeNotification`
- `com.apple.AppleMultitouchTrackpadDomainDidChangeNotification`

Source: `strings /System/Library/ExtensionKit/Extensions/TrackpadExtension.appex/Contents/MacOS/TrackpadExtension`.

**Recommended approach for the Host:**
1. Keep one `UserDefaults(suiteName:)` for TP and one for Dock, and KVO the handful of keys the Remote needs.
2. Also observe `com.apple.IOTrackpadPropertyDidChangeNotification`, `SwipeScrollDirectionDidChangeNotification` and `AppleEnableSwipeNavigateWithScrollsDidChangeNotification` by name.
3. On any of these signals, re-read the whole snapshot (a few dozen `object(forKey:)` calls served from the `cfprefsd` cache) and push it to the Remote if it changed.
4. Also send the snapshot on every Remote connect.

This avoids relying on any single undocumented notification. A slow poll (say every 5 s while a Remote is connected) is a safe fallback, because reads are cheap and always fresh.

## Caveats

- None of these keys or notification names are documented by Apple. They are the Settings app's private contract and may change in a future macOS. Treat a missing or unknown value as "use macOS default".
- Writing these keys with `defaults write` does not apply them to the driver until logout. Settings also pushes them over IOKit. That does not matter here, because the Host only reads.
- The "Inferred" encodings above need one pass of flipping each option in System Settings while running `defaults read com.apple.AppleMultitouchTrackpad`, `defaults read -g` and `defaults read com.apple.dock`, and diffing the output, if the Remote is to rely on them.

## Sources

- On-device:
  - `defaults read` of the domains above.
  - `ioreg -r -c AppleMultitouchTrackpadHIDEventDriver -l -d 1` (preference domain and default values per trackpad).
  - `ioreg -r -c IOHIDSystem -l -d 1` (live values).
  - Strings and `Localizable.loctable` of `/System/Library/ExtensionKit/Extensions/TrackpadExtension.appex` and `AccessibilitySettingsExtension.appex`.
  - System Settings → Trackpad, read through System Events (Accessibility API).
  - Swift test scripts for reading, KVO and distributed notifications.
- Apple: [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults), [UserDefaults.didChangeNotification](https://developer.apple.com/documentation/foundation/userdefaults/didchangenotification), [init(suiteName:)](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)), [Turn on three-finger drag](https://support.apple.com/en-us/102341), [Use Multi-Touch gestures on Mac](https://support.apple.com/en-us/102482).
