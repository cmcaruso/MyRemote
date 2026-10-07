import Hummingbird
import HummingbirdWebSocket
import HostCore

/// Serves the Remote and its WebSocket on loopback; `tailscale serve` adds HTTPS and the tailnet.
struct Server: Sendable {
    let remoteDirectory: String
    let port: Int
    let commands: AsyncStream<Command>.Continuation
    /// Called with +1 when a Remote connects and -1 when it leaves.
    let onRemote: @Sendable (Int) async -> Void

    func run() async throws {
        let router = Router()
        router.add(middleware: FileMiddleware(remoteDirectory, searchForIndexHtml: true))

        let commands = commands
        let onRemote = onRemote
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/ws") { inbound, _, _ in
            await onRemote(1)
            defer { Task { await onRemote(-1) } }
            for try await message in inbound.messages(maxSize: 1 << 16) {
                guard case let .text(text) = message, let command = Command(decoding: text) else { continue }
                commands.yield(command)
            }
        }

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        // The app owns its lifecycle: leave SIGTERM/SIGINT to quit the process, not just stop the server.
        try await app.runService(gracefulShutdownSignals: [])
    }
}
