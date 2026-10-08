# Posting Mac trackpad gestures from the Host (ticket #42)

Question: for each trackpad gesture on the map (pinch, smart zoom, rotate, swipe between pages, Mission Control, App Exposé, Spaces, Show Desktop, Launchpad/Apps, Notification Center, three-finger drag, Look up), can the **Host** post a real gesture event, or only a keyboard shortcut / CoreDock / symbolic-hotkey call? Is it continuous (follows the fingers) or discrete? What permissions does it need, and how much macOS-version risk does it carry?

Researched 2026-10-09. Sources: the SDK headers shipped with the installed Xcode (macOS 27.0 SDK), Mac Mouse Fix source (the most complete open-source gesture simulator, pinned to commit [`69261f5`](https://github.com/noah-nuebling/mac-mouse-fix/tree/69261f56f3096bdc26cf1e7cf4ae2efe1273606f)), other open-source projects, Apple Support, and **probes run on this Mac (macOS 26.6.2, build 25G83)**. Builds on [`input-apis.md`](https://github.com/cmcaruso/MyRemote/blob/research/input-apis/docs/research/input-apis.md) (branch `research/input-apis`). Claims are tagged with sources; see [Sources](#sources).

## TL;DR

- **There is no public API for this.** `NSEvent` can only *create* mouse, key, enter/exit and "other" events, plus wrap a `CGEvent` [S1]. `CGEventType` has no gesture types, and only the phase enum `CGGesturePhase` is public [S2]. Every real gesture event is a `CGEvent` whose type (29 = gesture, 30 = magnify/dock) and fields 110+ are set by number, which is undocumented. That is what Mac Mouse Fix, SensibleSideButtons and similar projects do [S3, S6].
- **On this Mac it all works.** Synthetic **pinch, rotate, smart zoom and navigation swipe** events reach AppKit as real `magnify`, `rotate`, `smartMagnify` and `swipe` events. Synthetic **dock swipes** drive **Mission Control, App Exposé, Spaces, Show Desktop and Apps** (the Launchpad replacement), and they **follow the fingers**: a half swipe that is held and then dragged back cancels cleanly. See [Probes](#probes-on-this-mac-macos-2662).
- **The risk is macOS 27.** It shipped in September 2026 and stopped honouring the dock-swipe `CGEvent` fields. Dock swipes now need an `IOHIDEvent` attached to the `CGEvent` through private SPI. Mac Mouse Fix does this by writing a pointer at hard-coded offsets inside the `CGEvent` struct, and has had lag, stuck-transition and inverted-velocity bugs on 27 since [S3, S4, S5]. Pinch, rotate, smart zoom and navigation swipe use a separate code path that Mac Mouse Fix left unchanged on 27, and I found no reports of breakage, but I haven't verified them on 27.
- **Discrete fallbacks are robust and verified here.** `CoreDockSendNotification` toggles Mission Control, App Exposé, Show Desktop and Apps [S8, S9]. The symbolic-hotkey shortcuts work too (Ctrl+↑/↓/←/→, F11), **but only if the posted flags include the fn bit (`0x800000`)** the hotkey is registered with: plain Ctrl+↑ did nothing. Notification Center opens by pressing the menu-bar clock through the Accessibility API.
- **Permissions:** everything needs only what the Host already has (Accessibility, which covers `PostEvent` and AX). `CoreDockSendNotification` triggered no prompt.
- **Recommendation:** ship pinch, smart zoom and rotate as real gesture events. Ship Mission Control, App Exposé, Spaces, Show Desktop and Apps as **discrete** actions (CoreDock or shortcut) first. Add continuous dock swipes later as an opt-in "feel" layer behind an OS-version check, with the discrete path as fallback. Notification Center goes through the AX clock press, Look up through Ctrl+Cmd+D. Three-finger drag needs nothing new: it is just a left-button drag.

## Per-gesture table

"Verified" means probed on this Mac (macOS 26.6.2); see [Probes](#probes-on-this-mac-macos-2662).

| Gesture (Apple's trackpad gesture [S10]) | Real event the Host can post | Continuous? | Discrete fallback | Permission | macOS-version risk | Recommendation |
|---|---|---|---|---|---|---|
| **Pinch to zoom** (2 fingers) | Type 29, subtype 8 (`kIOHIDEventTypeZoom`); field 113 = magnification delta (double); field 132 = phase (1 Began, 2 Changed, 4 Ended) [S3]. **Verified**: arrives as `NSEventTypeMagnify` and `magnifyWithEvent:` with matching `NSEventPhase`. | **Yes.** Each event carries a delta, with Began/Changed/Ended | Cmd+= / Cmd+- (app-dependent) | Accessibility (PostEvent) | Medium: private fields, unchanged since Mac Mouse Fix 2020 through 26; not reported broken on 27 (unverified) | **Do it.** Remote pinch → stream of magnify deltas |
| **Smart zoom** (2-finger double-tap) | Type 29, subtype 22 (`kIOHIDEventTypeZoomToggle`), no other fields [S3]. **Verified**: arrives as `smartMagnifyWithEvent:`. | No (one-shot) | none general | Accessibility | Medium (same family) | **Do it** |
| **Rotate** (2 fingers) | Type 29, subtype 5 (`kIOHIDEventTypeRotation`); field 114 = degrees (double); field 132 = phase [S3]. **Verified**: arrives as `rotateWithEvent:`. | **Yes** | app shortcuts (e.g. Cmd+R in Preview) | Accessibility | Medium | **Do it** (low priority; few apps use it) |
| **Swipe between pages** (2-finger horizontal) | (a) **Discrete** navigation swipe: type 29, subtype 16 (`kIOHIDEventTypeNavigationSwipe`), field 115 = direction mask (`kIOHIDSwipeLeft` 4 / `Right` 8), Began then Ended [S3, S6]. **Verified**: arrives as `swipeWithEvent:` (deltaX ±1). (b) **Continuous** (Safari's interactive page slide): the Host's existing phased scroll events **plus** a companion type 29 / subtype 6 (`kIOHIDEventTypeScroll`) gesture event per frame with fields 116/119 (dx/dy) and 132 (phase) [S7]. Not verified here. | (a) no, (b) **yes** | Cmd+[ / Cmd+], or Cmd+←/→. Mac Mouse Fix keeps a per-app table of which one works [S11] | Accessibility | Medium | Add (b) to `Scroller`/`Injector` (cheap) and check it in Safari; keep a **Back/Forward** button that posts (a) or Cmd+[ |
| **Mission Control** (3/4-finger up) | Dock swipe: type 30, subtype 23 (`kIOHIDEventTypeDockSwipe`), motion = **vertical (2)**, plus a companion type 29 event; field layout in [Dock swipes](#dock-swipes-in-detail) [S3]. **Verified**: progress −0.6 opens it, +0.6 closes it; held at −0.3 it is half-open, and dragging back then Cancelled closes it. | **Yes** | **CoreDock** `com.apple.expose.awake` (**verified** toggle); SHK 32 = **Ctrl+fn+↑** (**verified**; plain Ctrl+↑ didn't work) | Accessibility (dock swipe, keys); nothing observed for CoreDock | **High** for dock swipes (broke in 27, private struct poke needed); low for CoreDock/SHK (CoreDock used by yabai, Hammerspoon for years) | **Discrete first** (CoreDock); continuous dock swipe as opt-in later |
| **App Exposé** (3/4-finger down) | Dock swipe, vertical, positive progress. **Verified** (opens and closes). | **Yes** | CoreDock `com.apple.expose.front.awake` [S9]; SHK 33 = Ctrl+fn+↓ | as above | High / low | **Discrete first** |
| **Swipe between Spaces / full-screen apps** (3/4-finger horizontal) | Dock swipe, motion = **horizontal (1)**. One Space ≈ progress `1 + 1/(n−1)` for n Spaces (Mac Mouse Fix's scaling [S12]). **Verified**: −1.25 moved Space 4 → 3, +1.25 back; held at −0.5 the Dock built its transition (9 windows) and dragging back cancelled to the same Space. | **Yes** (the strip follows the fingers) | SHK 79/81 = **Ctrl+fn+←/→** (**verified** 4 → 3 → 4); no CoreDock call | Accessibility | High / low | **Discrete first** (Ctrl+fn+←/→); continuous dock swipe is the nicest gesture to add later |
| **Show Desktop** (thumb + 3 spread) | Dock swipe, motion = **pinch (3)**, **negative** progress (with field 136 "inverted" = 1). **Verified**: windows moved off-screen and the Dock's desktop window appeared. | **Yes** | CoreDock `com.apple.showdesktop.awake` (**verified** toggle); SHK 36 = F11 (+fn flag) | as above | High / low | **Discrete first** (CoreDock) |
| **Apps** (the Launchpad replacement on macOS 26; thumb + 3 pinch) | Dock swipe, pinch, **positive** progress. **Verified**: the Spotlight Apps panel opened. Didn't check that it tracks the fingers; Mac Mouse Fix reports it "extremely laggy and janky" on 27 [S3]. | Probably, unverified | CoreDock `com.apple.launchpad.toggle` (**verified**: toggles Apps on 26, although OpenLogi's code assumes it's a no-op [S9]); SHK 160 "Show Apps" exists but has **no binding** by default | as above | High / low-medium | **CoreDock** toggle |
| **Notification Center** (2-finger swipe from right edge) | No known working recipe. `IOHIDEvent` defines a `NotificationCenterPrimary` gesture flavor [S13], but no open-source project posts it, and the pre-27 field layout has no flavor field. | n/a | **AX press on the menu-bar clock** (`com.apple.controlcenter` → `AXExtrasMenuBar` → item `com.apple.menuextra.clock` → `AXPress`): **verified** open and close. SHK 163 exists but is **unbound** by default (binding it means writing the user's hotkey prefs, as Mac Mouse Fix does [S14]). | Accessibility (AX) | Low-medium (AX identifiers can change between releases) | **AX clock press** |
| **Three-finger drag** | Nothing gesture-specific: macOS turns it into an ordinary left-button drag (mouse down → dragged → up) [S10]. | Yes | n/a | Accessibility | Low | **Already supported** (`buttonDown` / `move` / `buttonUp`); only Remote-side mapping needed |
| **Look up** (3-finger tap / force click) | No known way to synthesize force-click pressure or the 3-finger tap. Mac Mouse Fix doesn't, and notes that "using LookUp by any other method except force touch is broken in Safari and Mail" [S3]. | n/a | SHK 70 = **Ctrl+Cmd+D** (enabled and bound on this Mac). Not verified visually | Accessibility | Low | **Ctrl+Cmd+D**, accept that it fails in Safari/Mail |

## How the gesture events are built

All of these come from reverse engineering (Nate Weaver's CalfTrail TouchSynthesis, then SensibleSideButtons, then Mac Mouse Fix [S3, S6]). The field numbers below are the ones in Mac Mouse Fix's [`TouchSimulator.m`](https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Touch/TouchSimulator.m) [S3] and the IOHID enums in [`IOHIDEventTypes.h`](https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Shared/IOKit/External/IOHIDEventTypes.h) [S13].

- Start from `CGEventCreate(NULL)` and set the type with `CGEventSetType(e, 29)` (field 55 is the type, so setting it is equivalent).
- **Field 110** = `IOHIDEventType` subtype: 5 rotation, 6 scroll, 8 zoom, 16 navigation swipe, 22 zoom toggle, 23 dock swipe.
- **Field 132** = phase, `IOHIDEventPhaseBits`: 1 Began, 2 Changed, 4 Ended, 8 Cancelled, 128 MayBegin. These are the same values as the public `CGGesturePhase` [S2]. AppKit maps them to `NSEventPhase` (Began 1, Changed 4, Ended 8), which the probe confirmed.
- **Field 113** = magnification (double), **114** = rotation in degrees (double), **115** = swipe direction mask, **116/119** = scroll-gesture dx/dy.
- Post at `kCGHIDEventTap` for pinch, rotate, smart zoom and navigation swipe; Mac Mouse Fix posts dock swipes and scroll-gesture companions at `kCGSessionEventTap`. Like scroll events, gesture events go to the **window under the pointer**. In Swift, `CGEventType(rawValue: 29)` and `CGEventField(rawValue: 110)` return `nil`, so set these through a tiny C/ObjC shim, or `unsafeBitCast` the raw `UInt32`.

### Dock swipes in detail

Before macOS 27 (this Mac), Mac Mouse Fix posts **two** events per frame [S3]:

- **Type 30 event:** field 110 = 23 (dock swipe); 132 and 134 = phase; 124 = cumulative "origin offset" (progress, double); 135 = the same offset as Float32 bits in an int64; 119 and 139 = motion as a denormal double (1.4e-45 horizontal, 2.8e-45 vertical, 4.2e-45 pinch); 123 and 165 = motion (1/2/3); 136 = "inverted from device" (natural scrolling); on Ended/Cancelled, 129 and 130 = exit speed (≈ last delta × 100); 41 = 33231 (purpose unknown).
- **Type 29 companion:** field 41 = 33231.

Driving it:

- **Progress units.** Vertical progress is roughly the finger travel ÷ screen height. Horizontal is `(1 + 1/(n−1)) / (screenWidth + 63)` per point for n Spaces [S12].
- **Ended vs Cancelled.** Mac Mouse Fix sends Ended only if the last delta has the same sign as the offset, otherwise Cancelled, so a swipe flicked back snaps back.
- **Lost end events.** It re-sends the end event after 0.2 s and 0.5 s, because the Dock sometimes drops it under load (the "stuck" bug) [S3].

From macOS 27 on, the `CGEvent` fields are ignored. Mac Mouse Fix's exploration [`FixDockSwipes.m`](https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Tests/FixDockSwipes.m) found that "removing type == 30 events breaks things", that "type == 29 events are not necessary", and that the data now lives in an attached `IOHIDEvent` [S4]. The fix [S3, S5]:

- Build a `HIDEvent` of type `DockSwipe` with fields Motion, Flavor = `DockPrimary`, Progress and the phase in its options, plus a `Velocity` child on exit.
- Attach it to a type-30 `CGEvent`, either with SkyLight's private `SLEventSetIOHIDEvent` or, as Mac Mouse Fix ships it, by **writing the pointer into the `CGEvent` at offsets `0x18` → `0xd0`**.

This is exactly the kind of thing that breaks silently in a point release. Since the 27 betas, the Mac Mouse Fix repo has accumulated issues and PRs about laggy, stuck, rebounding and inverted dock swipes on 27 [S5].

## Probes on this Mac (macOS 26.6.2)

Throwaway ObjC programs built with `clang -fobjc-arc -framework Cocoa`. Nothing was installed and no system setting was changed: the symbolic-hotkey bindings were only read. Each state the probes opened was closed again.

1. **Gesture probe.** A window under the pointer logged what AppKit delivered after the probe posted pinch (4 events), rotate (4), smart zoom and a left navigation swipe at `kCGHIDEventTap`. `CGPreflightPostEventAccess() = 1`. Output:
   ```
   -- magnify   → NSEvent type=30, magnifyWithEvent: magnification=0.100 phase=1 / 4 / 4, then 0.000 phase=8
   -- rotate    → NSEvent type=18, rotateWithEvent: rotation=5.000 phase=1 / 4 / 4, then 0.000 phase=8
   -- smart zoom→ NSEvent type=32, smartMagnifyWithEvent:
   -- nav swipe → NSEvent type=31, swipeWithEvent: dx=1.0 dy=0.0
   ```
2. **Dock-swipe probe** (pre-27 layout above, 20 Changed frames 8 ms apart, then Ended). State was read from `CGWindowListCopyWindowInfo` (Dock and Spotlight windows, layer-0 window positions) and `CGSGetActiveSpace` (5 Spaces on this display):
   - vertical −0.6 → Dock windows 1 → 5 (Mission Control); +0.6 → back to 1.
   - vertical +0.6 → 1 → 3 (App Exposé); −0.6 → back to 1.
   - vertical −0.3 held 0.5 s → 5 Dock windows mid-gesture; dragged back and Cancelled → 1.
   - horizontal −1.25 → active Space 4 → 3; +1.25 → 4. Horizontal −0.5 held → 9 Dock transition windows mid-gesture; dragged back and Cancelled → still Space 4.
   - pinch −0.6 → app windows moved to y < 0 and a full-screen Dock window appeared at layer 18 (Show Desktop). Pinch +0.6 → a Spotlight panel at layer 23 (Apps).
3. **Shortcuts.** Ctrl+↑ with flags `0x40000` (Ctrl only) did **nothing**. Ctrl+↑ with `0x840000` (Ctrl + fn) opened Mission Control and closed it again. Ctrl+fn+← / → moved Space 4 → 3 → 4. Read-only `CGSGetSymbolicHotKeyValue` on this Mac: 32 / 33 / 79 / 81 = arrows with mods `0x840000`; 36 = F11 (vkc 103) with `0x800000`; 70 = Ctrl+Cmd+D (`0x140000`); 160 (Show Apps) and 163 (Notification Center) disabled and unbound.
4. **CoreDock.** `CoreDockSendNotification`, resolved with `dlsym` from ApplicationServices, returned 0 and toggled `com.apple.expose.awake` (Mission Control), `com.apple.showdesktop.awake` and `com.apple.launchpad.toggle` (the Apps panel on 26) on and off.
5. **Notification Center.** `AXIsProcessTrusted() = 1`. `AXPress` on ControlCenter's `com.apple.menuextra.clock` opened a "Notification Center" window at layer 21, and a second press closed it.

Not probed: the continuous Safari page swipe (scroll plus type 29 / subtype 6), whether Apps tracks the fingers, Look up, and anything on macOS 27.

## Recommendation for MyRemote

1. **Now: pinch, smart zoom, rotate** as real events. Add `Command.magnify(delta, phase)`, `.rotate(degrees, phase)` and `.smartZoom` and post them from `Injector` through a small C shim for the raw type and field numbers. The Remote's two-finger pinch maps 1:1 to a continuous gesture.
2. **Now: discrete system actions.**
   - Mission Control, App Exposé, Show Desktop and Apps: `CoreDockSendNotification`, resolved with `dlsym` so a missing symbol just disables the button.
   - Spaces: the user's actual SHK 79/81 binding, read with `CGSGetSymbolicHotKeyValue` and posted **with the exact modifier mask, including fn**. Hard-coding Ctrl+fn+←/→ is acceptable for v1.
   - Notification Center: AX press on the clock.
   - Look up: Ctrl+Cmd+D (SHK 70).
3. **Next: page swipe.** Add the type 29 / subtype 6 companion events to the existing phased scroll in `Injector.post(_ scroll:)`, so a two-finger horizontal swipe slides pages in Safari. Verify there first. Keep a Back/Forward button (Cmd+[ / Cmd+]) as fallback.
4. **Later, opt-in: continuous dock swipes** for the 3/4-finger gestures (Spaces following the fingers is the big win). Gate on `ProcessInfo.operatingSystemVersion.majorVersion < 27` with the field-based recipe. On 27+, either port Mac Mouse Fix's `IOHIDEvent` attachment, accepting the struct-offset hack and its bugs, or fall back to the discrete actions. Re-send end events at 0.2 s and 0.5 s, and throttle Changed events to about 8 ms [S5].
5. **Three-finger drag:** nothing on the Host. Just map it on the Remote to the existing drag commands.

## Sources

- **[S1]** macOS 27.0 SDK, `AppKit.framework/Headers/NSEvent.h`: the only factory methods are `mouseEventWithType:`, `keyEventWithType:`, `enterExitEventWithType:`, `otherEventWithType:`, `eventWithCGEvent:` and `eventWithEventRef:`; gesture `NSEventType`s are 29 Gesture, 30 Magnify, 31 Swipe, 18 Rotate, 32 SmartMagnify and 34 Pressure. Online: https://developer.apple.com/documentation/appkit/nsevent
- **[S2]** macOS 27.0 SDK, `CoreGraphics.framework/Headers/CGEventTypes.h`: `CGGesturePhase` (Began 1, Changed 2, Ended 4, Cancelled 8, MayBegin 128) is public; no gesture `CGEventType` or gesture fields are.
- **[S3]** Mac Mouse Fix, `Helper/Core/Touch/TouchSimulator.m` (navigation swipe, smart zoom, rotation, magnification, dock swipes for pre-27 and 27; Look up note): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Touch/TouchSimulator.m ; motion constants in `TouchSimulator.h`: https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Touch/TouchSimulator.h
- **[S4]** Mac Mouse Fix, `Tests/FixDockSwipes.m` ("macOS 27 (Beta 2) broke DockSwipe simulation", the field-deletion experiments, `SLEventSetIOHIDEvent`): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Tests/FixDockSwipes.m ; the pointer-offset bridge `Shared/IOKit/CGEventHIDEventBridge.m`: https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Shared/IOKit/CGEventHIDEventBridge.m ; commit "Fix DockSwipes under macOS 27 (Beta 2)": https://github.com/noah-nuebling/mac-mouse-fix/commit/f92d2d53a0
- **[S5]** Mac Mouse Fix macOS 27 dock-swipe follow-ups: issues https://github.com/noah-nuebling/mac-mouse-fix/issues/2008 , https://github.com/noah-nuebling/mac-mouse-fix/issues/2038 ; PRs https://github.com/noah-nuebling/mac-mouse-fix/pull/1988 (lag, throttling to 8 ms), https://github.com/noah-nuebling/mac-mouse-fix/pull/2077 (inverted release velocity), https://github.com/noah-nuebling/mac-mouse-fix/pull/1936 (release rebound)
- **[S6]** SensibleSideButtons, `SBFFakeSwipe` navigation-swipe synthesis (lineage from CalfTrail TouchSynthesis): https://github.com/archagon/sensible-side-buttons/blob/f24c0ced598325182fa4c4a38f57223530a47adc/SensibleSideButtons/AppDelegate.m
- **[S7]** Mac Mouse Fix, `Helper/Core/Touch/GestureScrollSimulator.m` (`postGestureScrollEventWithGestureVector:`: scroll event + type 29 / subtype 6 companion "allows for swiping between pages in apps like Safari or Preview"): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Touch/GestureScrollSimulator.m
- **[S8]** yabai, `src/space_manager.c` (`CoreDockSendNotification(CFSTR("com.apple.expose.awake"))`, `com.apple.showdesktop.awake`): https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space_manager.c ; Hammerspoon `extensions/spaces/private.h`: https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/private.h
- **[S9]** OpenLogi, `crates/openlogi-inject/src/inject/macos/dock.rs` (CoreDock names for Mission Control, App Exposé `com.apple.expose.front.awake`, Show Desktop, Launchpad): https://github.com/AprilNEA/OpenLogi/blob/1505c6525470bc0a38ae3ba79d70e950347d2532/crates/openlogi-inject/src/inject/macos/dock.rs
- **[S10]** Apple Support, "Use Multi-Touch gestures on Mac" (gesture list and finger counts; Apps replaces Launchpad; three-finger drag is an Accessibility option): https://support.apple.com/en-us/102482
- **[S11]** Mac Mouse Fix, `Helper/Core/Actions/Actions.m` (per-app back/forward method: navigation swipe vs Cmd+[ etc.; smart zoom action): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Actions/Actions.m
- **[S12]** Mac Mouse Fix, `Helper/Core/Drag/ThreeFingerSwipe/ModifiedDragOutputThreeFingerSwipe.m` (progress scaling per Space and per screen height): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Drag/ThreeFingerSwipe/ModifiedDragOutputThreeFingerSwipe.m
- **[S13]** `IOHIDEventTypes.h` (from Apple's IOKitUser sources, vendored by Mac Mouse Fix): event types, swipe masks, gesture flavors incl. `NotificationCenterPrimary`, phase bits: https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Shared/IOKit/External/IOHIDEventTypes.h
- **[S14]** Mac Mouse Fix, `Helper/Core/Actions/SymbolicHotKeys.m` (posting SHKs; permanently binding unbound ones to an unreachable keycode because temporary rebinding is unreliable on 15/26) and `Various Notes/SymbolicHotKeys Reference.txt` (SHK ids 32, 33, 36, 70, 79, 81, 160, 163): https://github.com/noah-nuebling/mac-mouse-fix/blob/69261f56f3096bdc26cf1e7cf4ae2efe1273606f/Helper/Core/Actions/SymbolicHotKeys.m ; macOS 26 default table on this Mac: `/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources/en.lproj/DefaultShortcutsTable.xml` (160 = "Show Apps", 163 = "Show Notification Center", 222 = Stage Manager)
- **[S15]** For contrast, projects that *read* gestures but only *post* clicks or keys: Touch-Tab (gesture event tap → Cmd+Tab key events): https://github.com/ris58h/Touch-Tab/blob/HEAD/Touch-Tab/AppSwitcher.swift ; MiddleClick (three-finger tap → middle click): https://github.com/artginzburg/MiddleClick
