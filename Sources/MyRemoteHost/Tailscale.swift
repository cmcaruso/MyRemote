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

    static func checkServe(port: Int) async -> ServeCheck {
        guard let cli = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
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

    /// Runs the CLI and waits for it, killing it if it hangs (say, while Tailscale is starting).
    private static func run(_ path: String, _ arguments: [String]) throws -> (Int32, Data, String) {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        // Read before waiting, so a large output can't fill the pipe and block the CLI.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        var errors = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        watchdog.cancel()
        if process.terminationReason == .uncaughtSignal { errors = "the Tailscale CLI didn't answer" }
        return (process.terminationStatus, output, errors)
    }
}
