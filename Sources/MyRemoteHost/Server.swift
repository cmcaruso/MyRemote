import Foundation
import Hummingbird
import HummingbirdWebSocket
import HostCore
import HTTPTypes
import NIOWebSocket

/// What the Host sends a connected Remote.
enum Outgoing: Sendable {
    case text(String)
    /// Close the socket with `4401`: the Remote is no longer paired.
    case unpaired
}

/// The connected Remotes' outgoing queues, so the Host can push state (like the volume) to all of them.
actor Clients {
    private var outboxes: [UUID: (remote: Pairing.Remote.ID, outbox: AsyncStream<Outgoing>.Continuation)] = [:]

    func add(_ outbox: AsyncStream<Outgoing>.Continuation, remote: Pairing.Remote.ID) -> UUID {
        let id = UUID()
        outboxes[id] = (remote, outbox)
        return id
    }

    func remove(_ id: UUID) {
        outboxes.removeValue(forKey: id)?.outbox.finish()
    }

    func broadcast(_ text: String) {
        for (_, outbox) in outboxes.values { outbox.yield(.text(text)) }
    }

    /// Drops every connection of a revoked Remote, or of all Remotes when `remote` is nil.
    func unpair(_ remote: Pairing.Remote.ID?) {
        for (owner, outbox) in outboxes.values where remote == nil || owner == remote {
            outbox.yield(.unpaired)
        }
    }
}

/// Serves the Remote and its WebSocket on loopback; `tailscale serve` adds HTTPS and the tailnet.
struct Server: Sendable {
    let remoteDirectory: String
    let port: Int
    let commands: AsyncStream<Command>.Continuation
    let clients: Clients
    let pairings: PairingStore
    /// Called with +1 when a Remote connects (after it can receive broadcasts) and -1 when it leaves.
    let onRemote: @Sendable (Int) async -> Void

    /// The app's close code for a Remote that isn't (or is no longer) paired; the Remote shows Pairing.
    static let unpairedCloseCode: WebSocketErrorCode = .unknown(4401)

    func run() async throws {
        let commands = commands
        let clients = clients
        let pairings = pairings
        let onRemote = onRemote

        let router = Router()
        router.add(middleware: FileMiddleware(remoteDirectory, searchForIndexHtml: true))

        router.post("/pair") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 1024)
            let code = (try? JSONDecoder().decode(PairBody.self, from: body))?.code ?? ""
            switch await pairings.pair(Self.facts(request), code: code) {
            case let .paired(remote, cookie):
                return Self.json(.ok, ["name": remote.name], cookie: cookie)
            case let .refused(refusal):
                return Self.json(.forbidden, ["error": "\(refusal)"])
            }
        }

        router.post("/unpair") { request, _ -> Response in
            guard let remote = await pairings.unpair(Self.facts(request)) else {
                return Self.json(.forbidden, ["error": "notPaired"])
            }
            await clients.unpair(remote.id)
            return Self.json(.ok, [:], cookie: Pairing.clearedCookie)
        }

        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("/ws") { request, _ in
            // A browser can't read a refused handshake's status, so every Remote is let in and the unpaired
            // ones are closed with 4401 below. A paired Remote's cookie is sent again so it never expires.
            guard case let .paired(_, cookie) = await pairings.check(Self.facts(request)) else { return .upgrade([:]) }
            return .upgrade([.setCookie: cookie])
        } onUpgrade: { inbound, outbound, context in
            let remote: Pairing.Remote
            switch await pairings.check(Self.facts(context.request)) {
            case let .paired(paired, _):
                remote = paired
            case let .refused(refusal):
                try await outbound.close(Self.unpairedCloseCode, reason: "\(refusal)")
                return
            }
            let (outbox, continuation) = AsyncStream.makeStream(of: Outgoing.self)
            let id = await clients.add(continuation, remote: remote.id)
            await onRemote(1)
            defer { Task { await clients.remove(id); await onRemote(-1) } }

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await message in outbox {
                        switch message {
                        case let .text(text):
                            try await outbound.write(.text(text))
                        case .unpaired:
                            try await outbound.close(Self.unpairedCloseCode, reason: "notPaired")
                            return
                        }
                    }
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

    private struct PairBody: Decodable {
        var code: String
    }

    private static let tailscaleUserLogin = HTTPField.Name("Tailscale-User-Login")!

    /// The parts of a request Pairing decides on. `tailscale serve` keeps the browser's `Host`, and replaces
    /// any `Tailscale-User-Login` a client sends with the tailnet's own.
    private static func facts(_ request: Request) -> Pairing.Request {
        let cookies = request.headers[values: .cookie]
        return Pairing.Request(
            cookie: cookies.isEmpty ? nil : cookies.joined(separator: "; "),
            login: request.headers[tailscaleUserLogin],
            origin: request.headers[.origin],
            host: request.head.authority,
            userAgent: request.headers[.userAgent]
        )
    }

    private static func json(_ status: HTTPResponse.Status, _ fields: [String: String], cookie: String? = nil) -> Response {
        var headers: HTTPFields = [.contentType: "application/json", .cacheControl: "no-store"]
        if let cookie { headers[.setCookie] = cookie }
        // Encoding a dictionary of strings can't fail.
        let body = try! JSONEncoder().encode(fields)
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: body)))
    }
}
