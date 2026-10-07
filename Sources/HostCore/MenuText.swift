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
            return [address, MenuLine("Funnel is on: anyone on the internet can reach the Remote",
                                      copy: command("tailscale serve reset && \(serveCommand)"))]
        case .notServing:
            return [MenuLine("tailscale serve doesn't reach the Host", copy: command(serveCommand))]
        case let .unknown(reason):
            return [MenuLine("Can't check tailscale serve: \(reason)")]
        }
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
}
