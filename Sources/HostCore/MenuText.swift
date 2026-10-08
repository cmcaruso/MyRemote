import Foundation

/// A line of status in the menu, and optionally a menu item under it that copies something useful.
public struct MenuLine: Equatable, Sendable {
    public struct Copy: Equatable, Sendable {
        public var label: String
        public var text: String

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    public var text: String
    public var copy: Copy?

    public init(_ text: String, copy: Copy? = nil) {
        self.text = text
        self.copy = copy
    }
}

/// The menubar's wording, kept here so the app only lays it out.
public enum MenuText {
    public static func serve(_ check: ServeCheck, port: Int) -> [MenuLine] {
        let serveCommand = "tailscale serve --bg \(port)"
        switch check {
        case let .serving(url, funnel):
            let address = MenuLine("Remote at \(url)", copy: .init(label: "Copy Remote Address", text: url))
            guard funnel else { return [address] }
            return [address, MenuLine("Funnel is on: the Remote's address is public on the internet",
                                      copy: command("tailscale serve reset && \(serveCommand)"))]
        case .notServing:
            return [MenuLine("tailscale serve doesn't reach the Host", copy: command(serveCommand))]
        case let .unknown(reason):
            return [MenuLine("Can't check tailscale serve: \(reason)")]
        }
    }

    /// The Phone Mic's status, and how to get BlackHole when it's missing: without it there's no
    /// microphone a call can pick, only outputs like the speakers.
    public static func phoneMic(live: Bool, output: String?, blackHoleInstalled: Bool) -> [MenuLine] {
        let status = switch (live, output) {
        case (_, nil): "Phone Mic: no output to send it to"
        case let (true, output?): "Phone Mic: live → \(output)"
        case let (false, output?): "Phone Mic: off, sends to \(output)"
        }
        guard !blackHoleInstalled else { return [MenuLine(status)] }
        return [MenuLine(status),
                MenuLine("For calls, install BlackHole 2ch and choose it as the microphone",
                         copy: command("brew install --cask blackhole-2ch"))]
    }

    private static func command(_ text: String) -> MenuLine.Copy {
        .init(label: "Copy Command: \(text)", text: text)
    }

    public static func remotes(_ count: Int) -> String {
        switch count {
        case 0: "No Remote connected"
        case 1: "1 Remote connected"
        default: "\(count) Remotes connected"
        }
    }

    /// The Paired Remotes submenu's title.
    public static func pairedRemotes(_ count: Int) -> String {
        count == 0 ? "No paired Remotes" : "Paired Remotes (\(count))"
    }

    /// One row of the Paired Remotes submenu.
    public static func pairedRemote(name: String, pairedAt: Date, lastSeen: Date, now: Date,
                                    timeZone: TimeZone = .current) -> String {
        "\(name) · paired \(day(pairedAt, timeZone)) · last used \(ago(lastSeen, now: now, timeZone: timeZone))"
    }

    /// Time left on the live Pairing code, as m:ss.
    public static func countdown(until expires: Date, now: Date) -> String {
        let seconds = max(0, Int(expires.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func ago(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60): return "\(minutes / 60) h ago"
        default: return day(date, timeZone)
        }
    }

    /// "8 Oct": the menu is in English whatever the Mac's locale.
    private static func day(_ date: Date, _ timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en_GB"), timeZone: timeZone)
        style = style.day().month(.abbreviated)
        return date.formatted(style)
    }
}
