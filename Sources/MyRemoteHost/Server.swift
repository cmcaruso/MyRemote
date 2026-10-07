import Foundation
import Hummingbird
import HummingbirdWebSocket
import HostCore

/// The connected Remotes' outgoing queues, so the Host can push state (like the volume) to all of them.
actor Clients {
    private var outboxes: [UUID: AsyncStream<String>.Continuation] = [:]

    func add(_ outbox: AsyncStream<String>.Continuation) -> UUID {
        let id = UUID()
        outboxes[id] = outbox
        return id
    }

    func remove(_ id: UUID) {
        outboxes.removeValue(forKey: id)?.finish()
    }

    func broadcast(_ text: String) {
        for outbox in outboxes.values { outbox.yield(text) }
    }
}

/// Serves the Remote and its WebSocket on loopback; `tailscale serve` adds HTTPS and the tailnet.
struct Server: Sendable {
    let remoteDirectory: String
    let port: Int
    let commands: AsyncStream<Command>.Continuation
    let clients: Clients
    /// Called with +1 when a Remote connects (after it can receive broadcasts) and -1 when it leaves.
    let onRemote: @Sendable (Int) async -> Void

    func run() async throws {
        let router = Router()
        router.add(middleware: FileMiddleware(remoteDirectory, searchForIndexHtml: true))

        let commands = commands
        let clients = clients
        let onRemote = onRemote
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/ws") { inbound, outbound, _ in
            let (outbox, continuation) = AsyncStream.makeStream(of: String.self)
            let id = await clients.add(continuation)
            await onRemote(1)
            defer { Task { await clients.remove(id); await onRemote(-1) } }

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await text in outbox { try await outbound.write(.text(text)) }
                }
                for try await message in inbound.messages(maxSize: 1 << 16) {
                    guard case let .text(text) = message, let command = Command(decoding: text) else { continue }
                    commands.yield(command)
                }
                group.cancelAll()
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
