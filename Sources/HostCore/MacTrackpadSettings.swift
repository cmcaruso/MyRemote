import Foundation

/// The Mac trackpad settings the Remote follows: which Gestures are on and how many fingers each takes.
/// Pushed on connect and whenever they change:
/// `{"t":"tp","pinch":true,"rotate":true,"smartZoom":true,"pages":"2","spaces":3,"missionControl":3,
/// "appExpose":0,"showDesktop":true,"apps":true,"notificationCenter":true,"lookUp":true,
/// "threeFingerDrag":false,"followsFingers":true}`.
///
/// Only the Gesture settings: tap to click, secondary click and scroll direction stay the Remote's.
public struct MacTrackpadSettings: Equatable, Sendable {
    public var pinch: Bool
    public var rotate: Bool
    public var smartZoom: Bool
    public var pages: Pages
    /// Fingers for each swipe: 3, 4, or 0 when it's off.
    public var spaces: Int
    public var missionControl: Int
    public var appExpose: Int
    public var showDesktop: Bool
    public var apps: Bool
    public var notificationCenter: Bool
    /// Whether a three-finger tap does Look up: whenever the Mac's Look up isn't Off, Force Click
    /// included, since a phone can't force-click.
    public var lookUp: Bool
    public var threeFingerDrag: Bool
    /// Whether the Dock Gestures follow the fingers on this macOS, or happen at once. For display only.
    public var followsFingers: Bool

    /// Swipe between pages.
    public enum Pages: String, Sendable {
        case two = "2", three = "3", twoOrThree = "2or3", off
    }

    public init(pinch: Bool, rotate: Bool, smartZoom: Bool, pages: Pages, spaces: Int, missionControl: Int,
                appExpose: Int, showDesktop: Bool, apps: Bool, notificationCenter: Bool, lookUp: Bool,
                threeFingerDrag: Bool, followsFingers: Bool) {
        self.pinch = pinch
        self.rotate = rotate
        self.smartZoom = smartZoom
        self.pages = pages
        self.spaces = spaces
        self.missionControl = missionControl
        self.appExpose = appExpose
        self.showDesktop = showDesktop
        self.apps = apps
        self.notificationCenter = notificationCenter
        self.lookUp = lookUp
        self.threeFingerDrag = threeFingerDrag
        self.followsFingers = followsFingers
    }
}

extension MacTrackpadSettings {
    /// Where macOS keeps them. Global keys are read from the global domain (`UserDefaults.standard`).
    public static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"
    public static let dockDomain = "com.apple.dock"

    /// The trackpad driver's defaults (`ApplePreferencesDefaultPreferences` in the IORegistry), used for
    /// any key that's missing. The keys are the ones the Host reads.
    public static let trackpadDefaults: [String: Int] = [
        "TrackpadPinch": 1,
        "TrackpadRotate": 1,
        "TrackpadTwoFingerDoubleTapGesture": 1,
        "TrackpadThreeFingerHorizSwipeGesture": 2,
        "TrackpadFourFingerHorizSwipeGesture": 2,
        "TrackpadThreeFingerVertSwipeGesture": 2,
        "TrackpadFourFingerVertSwipeGesture": 2,
        "TrackpadFourFingerPinchGesture": 2,
        "TrackpadFiveFingerPinchGesture": 2,
        "TrackpadTwoFingerFromRightEdgeSwipeGesture": 3,
        "TrackpadThreeFingerTapGesture": 0,
        "TrackpadThreeFingerDrag": 0,
    ]
    /// macOS's defaults: two-finger page swipe on, Look up by Force Click.
    public static let globalDefaults: [String: Int] = [
        "AppleEnableSwipeNavigateWithScrolls": 1,
        "com.apple.trackpad.forceClick": 1,
    ]
    /// Missing means on, except App Exposé, which a new Mac has off.
    public static let dockDefaults: [String: Int] = [
        "showMissionControlGestureEnabled": 1,
        "showAppExposeGestureEnabled": 0,
        "showDesktopGestureEnabled": 1,
        "showLaunchpadGestureEnabled": 1,
    ]

    /// Interprets the raw values read from the three domains; a missing key takes its default.
    public init(trackpad: [String: Int], global: [String: Int], dock: [String: Int], followsFingers: Bool) {
        func tp(_ key: String) -> Int { trackpad[key] ?? Self.trackpadDefaults[key]! }
        func g(_ key: String) -> Int { global[key] ?? Self.globalDefaults[key]! }
        func d(_ key: String) -> Int { dock[key] ?? Self.dockDefaults[key]! }

        // A swipe takes three fingers when its three-finger key is 2 (the system gesture), else four
        // when the four-finger key is. Settings leaves the four-finger key at 2 when three is chosen.
        func fingers(three: String, four: String) -> Int {
            tp(three) == 2 ? 3 : tp(four) == 2 ? 4 : 0
        }
        let vertical = fingers(three: "TrackpadThreeFingerVertSwipeGesture", four: "TrackpadFourFingerVertSwipeGesture")
        // The thumb-and-fingers pinch: in for Apps, out for Show Desktop.
        let thumbPinch = tp("TrackpadFourFingerPinchGesture") == 2 || tp("TrackpadFiveFingerPinchGesture") == 2

        // Two fingers is a global switch; three fingers is the three-finger horizontal key at 1.
        let twoFingerPages = g("AppleEnableSwipeNavigateWithScrolls") != 0
        let threeFingerPages = tp("TrackpadThreeFingerHorizSwipeGesture") == 1
        let pages: Pages = switch (twoFingerPages, threeFingerPages) {
        case (true, true): .twoOrThree
        case (true, false): .two
        case (false, true): .three
        case (false, false): .off
        }

        self.init(
            pinch: tp("TrackpadPinch") != 0,
            rotate: tp("TrackpadRotate") != 0,
            smartZoom: tp("TrackpadTwoFingerDoubleTapGesture") != 0,
            pages: pages,
            spaces: fingers(three: "TrackpadThreeFingerHorizSwipeGesture", four: "TrackpadFourFingerHorizSwipeGesture"),
            missionControl: d("showMissionControlGestureEnabled") != 0 ? vertical : 0,
            appExpose: d("showAppExposeGestureEnabled") != 0 ? vertical : 0,
            showDesktop: thumbPinch && d("showDesktopGestureEnabled") != 0,
            // Launchpad's switch left the Trackpad pane in macOS 26 and its pinch now opens Apps. Turning
            // Show Desktop off clears the pinch keys too, so Apps goes with it.
            apps: thumbPinch && d("showLaunchpadGestureEnabled") != 0,
            notificationCenter: tp("TrackpadTwoFingerFromRightEdgeSwipeGesture") != 0,
            lookUp: tp("TrackpadThreeFingerTapGesture") == 2 || g("com.apple.trackpad.forceClick") != 0,
            threeFingerDrag: tp("TrackpadThreeFingerDrag") != 0,
            followsFingers: followsFingers
        )
    }

    /// Set to `1` at launch to make the Dock Gestures happen at once on any macOS, to try the fallback.
    public static let oneShotVariable = "MYREMOTE_ONE_SHOT_GESTURES"

    /// The Dock Gestures follow the fingers only on macOS 26, where their private events were tested
    /// (docs/adr/0001). Supporting a new macOS means testing it and widening this.
    public static func followsFingers(macOSMajor: Int, environment: [String: String]) -> Bool {
        macOSMajor == 26 && environment[oneShotVariable] != "1"
    }

    public func encoded() -> String {
        let fields: [String: Any] = [
            "t": "tp",
            "pinch": pinch, "rotate": rotate, "smartZoom": smartZoom, "pages": pages.rawValue,
            "spaces": spaces, "missionControl": missionControl, "appExpose": appExpose,
            "showDesktop": showDesktop, "apps": apps, "notificationCenter": notificationCenter,
            "lookUp": lookUp, "threeFingerDrag": threeFingerDrag, "followsFingers": followsFingers,
        ]
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
