import Foundation

/// The Mac's output volume as the Remote shows it, pushed on connect and whenever it changes:
/// `{"t":"vol","v":0.4,"muted":false,"settable":true}`.
public struct VolumeState: Equatable, Sendable {
    /// 0 to 1.
    public var level: Double
    public var muted: Bool
    /// Whether the output has a software volume the slider can set (HDMI and DisplayPort outputs often don't).
    public var settable: Bool

    public init(level: Double, muted: Bool, settable: Bool) {
        self.level = level
        self.muted = muted
        self.settable = settable
    }

    public func encoded() -> String {
        // CoreAudio levels are Float32 (0.4 reads 0.4000000059604645); three decimals is plenty for a slider.
        let v = (level * 1000).rounded() / 1000
        let fields: [String: Any] = ["t": "vol", "v": v, "muted": muted, "settable": settable]
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
