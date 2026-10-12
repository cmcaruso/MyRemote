import Foundation
import HostCore

/// Asks Tailscale's CLI whether `tailscale serve` reaches the Host. The CLI is optional: the Host serves
/// without it, and the menu only loses this check.
enum Tailscale {
    /// Where the Mac app, its "CLI integration" link and Homebrew put the CLI.
    private static let candidates = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
    ]

    private static var cli: String? { candidates.first(where: FileManager.default.isExecutableFile(atPath:)) }

    /// Whether Tailscale is on the Mac, for Setup's first step.
    static var installed: Bool { cli != nil }

    static func checkServe(port: Int) async -> ServeCheck {
        guard let cli else {
            return .unknown("Tailscale CLI not found")
        }
        return await Task.detached {
            do {
                let (status, output, errors) = try run(cli, ["serve", "status", "--json"])
                guard status == 0 else {
                    let reason = errors.split(separator: "\n").first.map(String.init) ?? "Tailscale isn't running"
                    return .unknown(reason)
                }
                return ServeCheck(statusJSON: output, port: port)
            } catch {
                return .unknown(error.localizedDescription)
            }
        }.value
    }

    /// Whether the Mac is logged in to a tailnet that can give it an HTTPS address. Nil when the CLI is
    /// missing or doesn't answer.
    static func status() async -> TailscaleStatus? {
        guard let cli else { return nil }
        return await Task.detached {
            guard let (_, output, _) = try? run(cli, ["status", "--json"]) else { return nil }
            return TailscaleStatus(statusJSON: output)
        }.value
    }

    enum ServeResult {
        case started
        /// The tailnet hasn't allowed Serve yet: the CLI waits for an admin to allow it at this address.
        case needsApproval(URL)
        case failed(String)
    }

    /// Runs `tailscale serve --bg` for the Host's port, on 443 unless something else is served there.
    static func startServe(port: Int) async -> ServeResult {
        guard let cli else { return .failed("Tailscale CLI not found") }
        return await Task.detached {
            do {
                let (_, current, _) = try run(cli, ["serve", "status", "--json"])
                guard let arguments = Setup.serveArguments(port: port, httpsPortsInUse: ServeCheck.portsInUse(statusJSON: current)) else {
                    return .failed("tailscale serve already uses ports 443, 8443 and 10000")
                }
                // The first time on a tailnet, the CLI prints an approval link and waits for it; don't wait long.
                let (status, output, errors) = try run(cli, arguments, timeout: 10)
                let text = String(decoding: output, as: UTF8.self) + "\n" + errors
                if let link = text.split(whereSeparator: \.isWhitespace)
                    .first(where: { $0.hasPrefix("https://login.tailscale.com/") })
                    .flatMap({ URL(string: String($0)) }) {
                    return .needsApproval(link)
                }
                guard status == 0 else {
                    return .failed(errors.split(separator: "\n").first.map(String.init) ?? "tailscale serve failed")
                }
                return .started
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
    }

    /// Runs the CLI and waits for it, killing it if it hangs (say, while Tailscale is starting).
    private static func run(_ path: String, _ arguments: [String], timeout: Double = 5) throws -> (Int32, Data, String) {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        // The Mac app's binary is also its CLI, and it acts as the CLI only when it looks run from a
        // terminal. Launched from a menubar app there's no TERM, so it tries to start the GUI instead.
        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "dumb"]) { current, _ in current }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Read before waiting, so a large output can't fill the pipe and block the CLI.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        var errors = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        watchdog.cancel()
        if process.terminationReason == .uncaughtSignal { errors = "the Tailscale CLI didn't answer\n" + errors }
        return (process.terminationStatus, output, errors)
    }
}
