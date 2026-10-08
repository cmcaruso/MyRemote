import Foundation
import HostCore

/// Reads the Mac trackpad settings and hears about changes made in System Settings, with no polling:
/// KVO on the trackpad and Dock domains, and the named distributed notifications Settings posts for
/// the global keys, which KVO doesn't report.
@MainActor
final class MacTrackpad: NSObject {
    /// Called on the main actor whenever any setting may have changed; `current()` tells whether one did.
    var onChange: (() -> Void)?

    private let trackpad = UserDefaults(suiteName: MacTrackpadSettings.trackpadDomain)!
    private let dock = UserDefaults(suiteName: MacTrackpadSettings.dockDomain)!
    private let followsFingers = MacTrackpadSettings.followsFingers(
        macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        environment: ProcessInfo.processInfo.environment)

    /// Posted by System Settings' Trackpad pane; wildcard observers get nothing, so the names are needed.
    private static let notifications = [
        "com.apple.IOTrackpadPropertyDidChangeNotification",
        "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification",
        "SwipeScrollDirectionDidChangeNotification",
        "AppleEnableSwipeNavigateWithScrollsDidChangeNotification",
        "3FHorizSwipeDidChangeNotification",
        "3FVertSwipeDidChangeNotification",
        "4FHorizSwipeDidChangeNotification",
        "4FVertSwipeDidChangeNotification",
    ]

    override init() {
        super.init()
        for key in MacTrackpadSettings.trackpadDefaults.keys {
            trackpad.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        for key in MacTrackpadSettings.dockDefaults.keys {
            dock.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        let center = DistributedNotificationCenter.default()
        for name in Self.notifications {
            center.addObserver(self, selector: #selector(changed), name: .init(name), object: nil)
        }
    }

    func current() -> MacTrackpadSettings {
        func read(_ defaults: UserDefaults, _ keys: Dictionary<String, Int>.Keys) -> [String: Int] {
            // `object(forKey:)`, so a missing key is told apart from 0 and takes the default.
            keys.reduce(into: [:]) { raw, key in raw[key] = defaults.object(forKey: key) as? Int }
        }
        return MacTrackpadSettings(
            trackpad: read(trackpad, MacTrackpadSettings.trackpadDefaults.keys),
            global: read(.standard, MacTrackpadSettings.globalDefaults.keys),
            dock: read(dock, MacTrackpadSettings.dockDefaults.keys),
            followsFingers: followsFingers)
    }

    // KVO from cfprefsd and distributed notifications can arrive on any thread.
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onChange?() } }
    }

    @objc nonisolated private func changed() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onChange?() } }
    }
}
