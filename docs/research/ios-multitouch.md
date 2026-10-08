# What multi-touch does iOS Safari give the Remote?

Research for [#44](https://github.com/cmcaruso/MyRemote/issues/44). Target: iOS 26, Safari and Home Screen web app.
Researched 2026-10-09. Sources are linked inline; the **Source quality** column / notes say when a claim rests on
anything weaker than Apple docs, WebKit source, or a WebKit bug.

## Short answer

- **Touches:** a page can track **up to 5 simultaneous touches** on iPhone, as Touch Events or Pointer Events (both
  available, every finger gets its own `identifier` / `pointerId`). A 6th finger is reported to **cancel every touch**.
  So 3- and 4-finger gestures fit; 5 is the ceiling.
- **Pinch/rotate:** WebKit's `gesturestart` / `gesturechange` / `gestureend` (`scale`, `rotation`) are shipped on iOS
  Safari. They're non-standard and their exact interplay with Touch Events lives in closed WebKit code, so the safe
  plan is to **compute pinch scale and rotation ourselves from the touch points** (we already have them in
  `trackpad.js`) and treat gesture events as optional.
- **What the page can stop:** everything WebKit itself does with the touch — scrolling, pinch-zoom, double-tap zoom,
  text selection, the long-press callout. `preventDefault()` in a non-passive `touchstart`/`touchmove` (which
  `listen()` already does) plus `touch-action: none` (already on `.pad`) covers it.
- **What the page cannot stop:** anything iOS or Safari's chrome owns rather than the web content: the **three-finger
  editing gestures** (undo/redo swipe, copy/cut/paste pinch, the three-finger-tap shortcut bar) —
  [WebKit bug 250792](https://bugs.webkit.org/show_bug.cgi?id=250792), still open —, the **home-indicator swipe**,
  **Control Center / Notification Center** pulls, **Reachability**, the **back/forward edge swipe** (Safari, when
  there's history), and accessibility gestures (Zoom, VoiceOver). Running as a Home Screen web app removes Safari's own
  chrome gestures but not the system ones.
- **Biggest practical hazard:** the three-finger editing gestures act on the **focused text field**. In Keyboard Mode
  the hidden `<textarea>` is focused, and its `input` handler forwards every change to the Mac — so a three-finger swipe
  on the pad could fire an iOS undo that becomes real backspaces on the Mac, and a three-finger "un-pinch" could paste
  the iPhone clipboard into the Mac. A 3-finger design has to handle this (see [Implications](#implications-for-the-remote)).

## What the Remote does today

- `listen()` in `remote/app.js` adds `touchstart`/`touchmove`/`touchend`/`touchcancel` with `{ passive: false }` and
  calls `e.preventDefault()` on every one (except on buttons), then feeds `e.targetTouches` to the recognizer.
- `remote/trackpad.js` knows 1 finger (move, tap, drag) and "2 or more" (scroll, 2-finger tap = right click). Three or
  four fingers are currently treated as "two".
- CSS: `.pad`, `.strip`, `.slider` and Present's surfaces have `touch-action: none`; `html, body` have
  `touch-action: manipulation`; `*` has `-webkit-user-select: none` and `-webkit-touch-callout: none`.
- Viewport: `width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no`; `apple-mobile-web-app-capable`
  and a manifest with `"display": "standalone"`.

## 1. How many touches?

| Claim | Source | Quality |
| --- | --- | --- |
| `navigator.maxTouchPoints` is **hard-coded to 5** on iOS (0 if a quirk/setting asks), not read from hardware. | WebKit [`Navigator::maxTouchPoints`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/Navigator.cpp) (`#if ENABLE(IOS_TOUCH_EVENTS) … return 5;`), and the iOS layout-test expectation [`navigator-maxtouchpoints-expected.txt`](https://github.com/WebKit/WebKit/blob/main/LayoutTests/platform/ios/js/dom/navigator-maxtouchpoints-expected.txt) (`= 5`). | Primary |
| iPhone hardware/UIKit tracks **5 simultaneous touches and cancels them all on the 6th**; iPads track more (11, iPad Pro 17). | [Apple Developer Forums 17606](https://developer.apple.com/forums/thread/17606) (developer measurements, 2015; not Apple staff, "undocumented, subject to change"). | Secondary — **verify on device** |
| Touch Events give `touches` / `targetTouches` / `changedTouches`; a sequence is delivered to the element that got the first `touchstart`, wherever the fingers move. | Apple, [Safari Web Content Guide – Handling Events](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/HandlingEvents/HandlingEvents.html) | Primary (archived) |
| Pointer Events on iOS Safari since **13**; `getCoalescedEvents` / `getPredictedEvents` since **18.2**. Each finger gets its own `pointerId`. | [MDN browser-compat-data, PointerEvent](https://github.com/mdn/browser-compat-data/blob/main/api/PointerEvent.json) | Primary-ish (curated compat data) |

Notes:

- `navigator.maxTouchPoints === 5` tells us nothing about the real limit (it's a constant), so don't use it to decide
  whether 4-finger gestures are available.
- `targetTouches` only lists touches that **started on the pad**. A finger that lands on the mode bar or the strip goes
  to that element, so it never joins a pad gesture. That's fine for the pad (it's large) but the recognizer should not
  assume `e.touches.length === e.targetTouches.length`.
- Touch-action is resolved **per touch identifier at touch-down** (WebKit
  [`_handleTouchActionsForTouchEvent`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm)
  looks up `touchActionsForPoint` for each new touch point). A finger that starts outside the pad gets
  `touch-action: manipulation` from `body`, which still allows pinch-zoom.

## 2. WebKit gesture events (pinch / rotate)

- **Exist on iOS:** `gesturestart`, `gesturechange`, `gestureend`, interface `GestureEvent` with `scale` (1.0 at start,
  relative to the initial finger distance) and `rotation` (degrees, clockwise positive).
  [Apple Safari Web Content Guide](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/HandlingEvents/HandlingEvents.html),
  [MDN GestureEvent](https://developer.mozilla.org/en-US/docs/Web/API/GestureEvent) (non-standard, WebKit only).
  WebKit's iOS test expectation
  [`gesture-event-basic-expected.txt`](https://github.com/WebKit/WebKit/blob/main/LayoutTests/platform/ios/fast/events/touch/gesture-event-basic-expected.txt)
  shows `GestureEvent` **is** exposed on iOS and the events carry `clientX`/`clientY` too.
- **Cancellable and blocking:** WebKit tracks non-passive `gesturestart`/`gesturechange`/`gestureend` listeners as
  "synchronous" event regions, alongside touch and pointer listeners
  ([`EventTrackingRegions.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/EventTrackingRegions.h),
  [`EventRegion.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/rendering/EventRegion.cpp)
  `NonPassiveGestureStart`). Apple's guide uses `preventDefault()` in `gesturechange` to "disable browser zoom".
- **Interplay with Touch Events is not documented.** Apple only says gesture events are sent "during a multi-touch
  sequence". On iOS, touch and gesture dispatch is in closed source: `EventHandlerIOS.mm` does
  `#import <WebKitAdditions/EventHandlerIOSTouch.cpp>`
  ([source](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/ios/EventHandlerIOS.mm)). So whether
  gesture events still fire after `touchstart` was prevented, their order relative to `touchmove`, and what they do
  with 3+ fingers are **on-device checks**.
- **Recommendation:** derive pinch and rotate from `targetTouches` in `trackpad.js` (distance and angle between the
  first two fingers, or the spread/angle of all fingers around the centroid). That keeps the recognizer pure and
  testable in Node, and works with 3 or 4 fingers. Use gesture events only if device testing shows they're better.

## 3. How WebKit decides what `preventDefault()` can block

The key mechanism is in WebKit's iOS content view,
[`WKContentViewInteraction.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm):

- WebKit installs **"deferring" gesture recognizers** that make native gestures wait while a non-passive
  `touchstart`/`touchmove`/`touchend` runs; if the page calls `preventDefault()`, `_touchEvent:preventsNativeGestures:`
  marks the touch "default prevented" and the waiting native gestures fail.
- `deferringGestureRecognizer:shouldDeferOtherGestureRecognizer:` only defers gestures **installed on or under the
  web view** — plus any Safari explicitly opts in via a private delegate method
  (`_webView:gestureRecognizerCanBePreventedByTouchEvents:`). Gestures elsewhere in the window or in the system are
  never deferred.
- The `touchmove` deferrer only defers **pan and pinch** recognizers (scrolling, zooming).
- The **back/forward navigation swipe** is special-cased the other way: `_touchEventsMustRequireGestureRecognizerToFail`
  returns YES for `_isNavigationSwipeGestureRecognizer`, i.e. the page's touch events wait for the edge swipe, not the
  reverse. A page cannot prevent it.

That is why `preventDefault()` reliably stops scroll / zoom / selection / callouts on the pad, but cannot stop
system-level gestures.

## 4. System gestures vs. the pad

"Safari" = in a Safari tab. "Web app" = opened from the Home Screen in standalone mode (on iOS 26 every site added to
the Home Screen opens as a web app by default — [heise](https://heise.de/-10749652), secondary).

| Gesture | Who owns it | Can the page stop it? | How / why |
| --- | --- | --- | --- |
| Page **pinch-zoom** | WebKit (scroll view) | **Yes** on the pad | `touch-action: none` on `.pad` + `preventDefault()` on touch events (pinch is deferred by WebKit, §3). `user-scalable=no` is **ignored** in Safari since iOS 10 ([WebKit blog](https://webkit.org/blog/7367/new-interaction-behaviors-in-ios-10/)). Outside the pad, `body`'s `touch-action: manipulation` still allows pinch-zoom; whether standalone honours `user-scalable=no` is unconfirmed → **verify**. |
| **Double-tap zoom** | WebKit | **Yes** | `touch-action: manipulation` or `none` ([WebKit blog, "More Responsive Tapping"](https://webkit.org/blog/5610/more-responsive-tapping-on-ios/)); `width=device-width` at scale 1 also disables it. |
| **Scrolling / rubber-band** | WebKit | **Yes** | `touch-action: none`, `preventDefault()`, `overflow: hidden`, `overscroll-behavior: none` (all already in place). |
| **Text selection / loupe / long-press callout** | WebKit | **Yes** | `-webkit-user-select: none`, `-webkit-touch-callout: none` (already global), plus `preventDefault()` on `touchstart` defers WebKit's text-interaction gestures. The focused `<textarea>` is the exception (`user-select: text`). |
| **Three-finger swipe left/right = undo/redo**, three-finger double-tap = undo | UIKit editing interaction (system, iOS 13+) | **No** | [WebKit bug 250792](https://bugs.webkit.org/show_bug.cgi?id=250792) (NEW since 2023, rdar://104664887): undo/redo still fires with `preventDefault()` on every touch event. Native apps opt out with `UIResponder.editingInteractionConfiguration = .none` ([Apple](https://developer.apple.com/documentation/uikit/uiresponder/editinginteractionconfiguration)); WebKit doesn't override it anywhere in its source, and pages have no equivalent. |
| **Three-finger pinch = copy (twice = cut), un-pinch = paste** | UIKit editing interaction | **No** | Same mechanism and bug as above. Gesture list: [Apple Pages/Keynote guide](https://support.apple.com/guide/pages-ipad/tana7e101d4c/ipados), [Macworld](https://www.macworld.com/article/3410596/ios-13-and-ipados-13-how-to-use-the-new-gestures-for-cut-copy-paste-undo-and-redo.html). |
| **Three-finger single tap = shortcut bar** (undo / cut / copy / paste) | UIKit editing interaction | **No** (no known fix) | [Apple Developer Forums 716058](https://developer.apple.com/forums/thread/716058): web game with no editable text asks how to disable it; no answer. Whether it appears with **no** focused editable element on iOS 26 → **verify**. |
| **Home indicator swipe up** (home / app switcher), **swipe along bottom edge** (switch apps) | SpringBoard | **No** | Native apps can only *defer* it (needs a second swipe) via `preferredScreenEdgesDeferringSystemGestures` / `prefersHomeIndicatorAutoHidden` on a `UIViewController` ([Apple](https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures)). No web equivalent. |
| **Notification Center** (pull from top-left/centre), **Control Center** (pull from top-right) | SpringBoard | **No** | Same as above: "the screen-edge gestures defined by the system take precedence over any gesture recognizers that you define" (Apple, same doc). The pad reaches the top of the screen, so a touch that starts on its top edge can be stolen. |
| **Reachability** (swipe down on the bottom edge) | SpringBoard | **No** | Off by default; user turns it on in Settings › Accessibility › Touch ([Apple iPhone guide](https://support.apple.com/guide/iphone/touch-iph77bcdd132/ios)). Portrait only. |
| **Back/forward edge swipe** | Safari / WKWebView | **No** | Touch events must wait for it (§3). Only does anything if the tab has history to go to. In a standalone web app → **verify** whether it exists at all. |
| **Safari's bottom bar swipe** (switch tabs) | Safari chrome | **No** | Outside web content. Gone in standalone mode. |
| **Accessibility Zoom** (3-finger double-tap, 3-finger drag), **VoiceOver** | System, opt-in | **No** | User settings; out of scope, but worth knowing they swallow 3-finger input when enabled. |

Summary for the pad: the only things that can fight a 3- or 4-finger gesture **in the middle of the pad** are the
UIKit editing gestures. Everything else lives on the screen edges.

## Implications for the Remote

1. **Prefer the Home Screen web app.** It removes Safari's tab-bar swipe and (probably) the back swipe, and gives the pad
   more of the screen. System edge gestures remain either way.
2. **Keep gestures off the edges.** Don't make a gesture depend on a finger starting within roughly 20 pt of the top or
   bottom edge of the screen. The pad's top edge is the risky one (Notification / Control Center).
3. **Three-finger gestures and the focused textarea.** Before shipping any 3-finger gesture:
   - Blur `field` when a third finger lands on the pad (or whenever the pad is touched with ≥ 3 fingers), so the
     editing gestures have no text to act on — but that dismisses the iOS keyboard, so maybe only outside Keyboard Mode.
   - And/or listen for `beforeinput` on `field` and cancel (or translate into ⌘Z / ⌘⇧Z / ⌘V for the Mac) events whose
     `inputType` is `historyUndo`, `historyRedo`, `insertFromPaste`, `deleteByCut`. Whether iOS fires these as
     cancellable `beforeinput` for the system gestures → **verify**.
   - Expect the "Undo" HUD / shortcut bar to appear sometimes regardless (bug 250792); design gestures so that a
     stray HUD is harmless.
   - Prefer **4-finger** gestures for actions that must be reliable, if testing shows iOS leaves 4 fingers alone.
4. **Pinch / rotate from touch points**, not from gesture events (§2). Two-finger pinch on the pad is safe: page zoom is
   already blocked there.
5. **Five-finger ceiling.** Never require 5 fingers, and treat a `touchcancel` of all fingers as "abort the gesture"
   (it already maps to `end`).

## On-device checklist (iPhone, iOS 26)

Test each in **Safari** and in the **Home Screen web app**. A throwaway page that logs every `touch*`, `pointer*`,
`gesture*` and `beforeinput` event with `touches.length`, `scale`, `rotation`, `defaultPrevented` and timestamps on a
`touch-action: none` div with non-passive `preventDefault()` handlers will answer most of these in one session.

- [ ] Put 3, 4, 5, then 6 fingers on the pad: do 3–5 all show up in `targetTouches` and as separate `pointerId`s? Does
      the 6th finger send `touchcancel` / `pointercancel` for all of them?
- [ ] Do `gesturestart` / `gesturechange` / `gestureend` fire on the pad **while `touchstart` is prevented**? In which
      order relative to `touchstart` / `touchmove`? Do they fire for 3 and 4 fingers, and what do `scale`/`rotation`
      mean then?
- [ ] Two-finger pinch and rotate on the pad: any page zoom? Any zoom when one finger starts on the pad and the other on
      the mode bar?
- [ ] With **no** text field focused (Trackpad Mode): three-finger swipe left/right, three-finger double-tap,
      three-finger pinch in/out, three-finger single tap. Does any HUD or shortcut bar appear? Do touch events keep
      flowing, or do we get `touchcancel`?
- [ ] Same, in **Keyboard Mode** with the textarea focused and some text typed: does the textarea's value change? Does
      `beforeinput` fire with `historyUndo` / `historyRedo` / `insertFromPaste`, and does `preventDefault()` on it stop
      the change? (Be ready for real keystrokes to reach the Mac — test with a scratch text document focused there.)
- [ ] Same three-finger moves with **four** fingers: does iOS ignore them?
- [ ] Start a swipe on the very top of the pad (left side and right side): do Notification Center / Control Center
      win? How close to the edge is still safe?
- [ ] Start a swipe near the bottom of the pad / home indicator: any app switching or Reachability (with Reachability
      on)?
- [ ] Swipe in from the left screen edge across the pad: back navigation in Safari (after visiting another page first)?
      Anything in the web app?
- [ ] In the web app, pinch on a non-pad area (mode bar, panel): does `user-scalable=no` stop zoom there?

## Sources

Primary:
- WebKit source: [`WKContentViewInteraction.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm),
  [`EventHandlerIOS.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/ios/EventHandlerIOS.mm),
  [`Navigator.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/Navigator.cpp),
  [`EventTrackingRegions.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/EventTrackingRegions.h),
  layout tests [`gesture-event-basic`](https://github.com/WebKit/WebKit/blob/main/LayoutTests/platform/ios/fast/events/touch/gesture-event-basic-expected.txt),
  [`navigator-maxtouchpoints`](https://github.com/WebKit/WebKit/blob/main/LayoutTests/platform/ios/js/dom/navigator-maxtouchpoints-expected.txt)
- [WebKit bug 250792 — Undo/redo triggered with 3-finger gestures even after preventDefault()](https://bugs.webkit.org/show_bug.cgi?id=250792)
- WebKit blog: [New Interaction Behaviors in iOS 10](https://webkit.org/blog/7367/new-interaction-behaviors-in-ios-10/),
  [More Responsive Tapping on iOS](https://webkit.org/blog/5610/more-responsive-tapping-on-ios/)
- Apple: [Safari Web Content Guide – Handling Events](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/HandlingEvents/HandlingEvents.html),
  [`editingInteractionConfiguration`](https://developer.apple.com/documentation/uikit/uiresponder/editinginteractionconfiguration),
  [`preferredScreenEdgesDeferringSystemGestures`](https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures),
  [iPhone User Guide – Touch / Reachability](https://support.apple.com/guide/iphone/touch-iph77bcdd132/ios)
- MDN: [GestureEvent](https://developer.mozilla.org/en-US/docs/Web/API/GestureEvent),
  [browser-compat-data](https://github.com/mdn/browser-compat-data) (PointerEvent, touch-action)

Secondary (corroboration only):
- [Apple Developer Forums 17606](https://developer.apple.com/forums/thread/17606) (touch limits),
  [716058](https://developer.apple.com/forums/thread/716058) (three-finger menu in a web game),
  [Macworld on iOS 13 editing gestures](https://www.macworld.com/article/3410596/ios-13-and-ipados-13-how-to-use-the-new-gestures-for-cut-copy-paste-undo-and-redo.html),
  [heise on iOS 26 web apps](https://heise.de/-10749652)
