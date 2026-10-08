import Foundation
import HostCore
import Testing

@Suite("Reading the Mac trackpad settings")
struct MacTrackpadSettingsTests {
    private func settings(trackpad: [String: Int] = [:], global: [String: Int] = [:], dock: [String: Int] = [:],
                          followsFingers: Bool = true) -> MacTrackpadSettings {
        MacTrackpadSettings(trackpad: trackpad, global: global, dock: dock, followsFingers: followsFingers)
    }

    @Test func missingKeysTakeTheDefaultsOfANewMac() {
        #expect(settings() == MacTrackpadSettings(
            pinch: true, rotate: true, smartZoom: true, pages: .two, spaces: 3, missionControl: 3,
            appExpose: 0, showDesktop: true, apps: true, notificationCenter: true, lookUp: true,
            threeFingerDrag: false, followsFingers: true))
    }

    @Test func switchesTurnOff() {
        let off = settings(
            trackpad: ["TrackpadPinch": 0, "TrackpadRotate": 0, "TrackpadTwoFingerDoubleTapGesture": 0,
                       "TrackpadTwoFingerFromRightEdgeSwipeGesture": 0],
            dock: ["showDesktopGestureEnabled": 0, "showLaunchpadGestureEnabled": 0])
        #expect(!off.pinch && !off.rotate && !off.smartZoom && !off.notificationCenter)
        #expect(!off.showDesktop && !off.apps)
    }

    @Test func swipesTakeThreeFingersWhenTheThreeFingerKeyIsTheSystemGesture() {
        let s = settings(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 2, "TrackpadFourFingerHorizSwipeGesture": 2,
                                    "TrackpadThreeFingerVertSwipeGesture": 2, "TrackpadFourFingerVertSwipeGesture": 2],
                         dock: ["showAppExposeGestureEnabled": 1])
        #expect(s.spaces == 3 && s.missionControl == 3 && s.appExpose == 3)
    }

    @Test func swipesTakeFourFingersWhenOnlyTheFourFingerKeyIs() {
        let s = settings(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 1, "TrackpadThreeFingerVertSwipeGesture": 0],
                         dock: ["showAppExposeGestureEnabled": 1])
        #expect(s.spaces == 4 && s.missionControl == 4 && s.appExpose == 4)
    }

    @Test func swipesAreOffWhenNeitherKeyIsTheSystemGesture() {
        let s = settings(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": 0, "TrackpadFourFingerHorizSwipeGesture": 0,
                                    "TrackpadThreeFingerVertSwipeGesture": 0, "TrackpadFourFingerVertSwipeGesture": 0],
                         dock: ["showAppExposeGestureEnabled": 1])
        #expect(s.spaces == 0 && s.missionControl == 0 && s.appExpose == 0)
    }

    @Test func theDockSwitchesTurnMissionControlAndAppExposeOff() {
        let s = settings(dock: ["showMissionControlGestureEnabled": 0, "showAppExposeGestureEnabled": 0])
        #expect(s.missionControl == 0 && s.appExpose == 0)
    }

    @Test(arguments: [
        (1, 1, MacTrackpadSettings.Pages.twoOrThree),
        (1, 2, .two),
        (0, 1, .three),
        (0, 2, .off),
    ])
    func swipeBetweenPages(twoFingers: Int, threeFingerHoriz: Int, pages: MacTrackpadSettings.Pages) {
        let s = settings(trackpad: ["TrackpadThreeFingerHorizSwipeGesture": threeFingerHoriz],
                         global: ["AppleEnableSwipeNavigateWithScrolls": twoFingers])
        #expect(s.pages == pages)
    }

    @Test func showDesktopOffClearsThePinchSoAppsGoesToo() {
        // What System Settings writes for Show Desktop off.
        let s = settings(trackpad: ["TrackpadFourFingerPinchGesture": 0, "TrackpadFiveFingerPinchGesture": 0],
                         dock: ["showDesktopGestureEnabled": 0])
        #expect(!s.showDesktop && !s.apps)
    }

    @Test(arguments: [
        (2, 0, true),  // Tap with Three Fingers
        (0, 1, true),  // Force Click with One Finger: the Remote taps with three instead
        (0, 0, false), // Off
    ])
    func lookUpIsOnUnlessTheMacsLookUpIsOff(threeFingerTap: Int, forceClick: Int, on: Bool) {
        let s = settings(trackpad: ["TrackpadThreeFingerTapGesture": threeFingerTap],
                         global: ["com.apple.trackpad.forceClick": forceClick])
        #expect(s.lookUp == on)
    }

    @Test func readsThreeFingerDrag() {
        #expect(settings(trackpad: ["TrackpadThreeFingerDrag": 1]).threeFingerDrag)
    }

    @Test(arguments: [
        (26, [:], true),
        (26, ["MYREMOTE_ONE_SHOT_GESTURES": "1"], false),
        (15, [:], false),
        (27, [:], false),
    ])
    func dockGesturesFollowTheFingersOnlyOnMacOS26(major: Int, environment: [String: String], follows: Bool) {
        #expect(MacTrackpadSettings.followsFingers(macOSMajor: major, environment: environment) == follows)
    }

    @Test func encodesEveryField() throws {
        let text = settings(followsFingers: false).encoded()
        let fields = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
        #expect(fields == [
            "t": "tp", "pinch": true, "rotate": true, "smartZoom": true, "pages": "2", "spaces": 3,
            "missionControl": 3, "appExpose": 0, "showDesktop": true, "apps": true, "notificationCenter": true,
            "lookUp": true, "threeFingerDrag": false, "followsFingers": false,
        ])
    }
}
