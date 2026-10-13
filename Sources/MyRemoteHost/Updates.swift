import Foundation
@preconcurrency import Sparkle

/// Updates from GitHub Releases through Sparkle. Only the Release build has a feed (scripts/dmg.sh
/// adds `SUFeedURL`), so a build from source never replaces itself with the published DMG.
@MainActor @Observable
final class Updates {
    /// Whether this build updates itself; the menu shows Check for Updates only then.
    let available: Bool
    /// False while Sparkle is already checking or installing.
    private(set) var canCheck = false

    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            available = false
            controller = nil
            return
        }
        available = true
        // Checks daily (SUEnableAutomaticChecks) and asks before installing, in Sparkle's own window.
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        canCheck = controller.updater.canCheckForUpdates
        // Sparkle changes it on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: .new) { [weak self] _, change in
            MainActor.assumeIsolated { self?.canCheck = change.newValue ?? false }
        }
    }

    func check() {
        controller?.checkForUpdates(nil)
    }
}
