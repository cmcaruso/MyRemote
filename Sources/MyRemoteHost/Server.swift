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
    /// `/ws` carries commands and gets the Host's broadcasts; `/mic` only streams the Phone Mic.
    enum Kind { case control, mic }

    private var outboxes: [UUID: (remote: Pairing.Remote.ID, kind: Kind, outbox: AsyncStream<Outgoing>.Continuation)] = [:]

    func add(_ outbox: AsyncStream<Outgoing>.Continuation, remote: Pairing.Remote.ID, kind: Kind = .control) -> UUID {
        let id = UUID()
        outboxes[id] = (remote, kind, outbox)
        return id
    }

    func remove(_ id: UUID) {
        outboxes.removeValue(forKey: id)?.outbox.finish()
    }

    func broadcast(_ text: String) {
        for (_, kind, outbox) in outboxes.values where kind == .control { outbox.yield(.text(text)) }
    }

    /// Drops every connection of a revoked Remote, or of all Remotes when `remote` is nil.
    func unpair(_ remote: Pairing.Remote.ID?) {
        for (owner, _, outbox) in outboxes.values where remote == nil || owner == remote {
            outbox.yield(.unpaired)
        }
    }
}

/// One Remote's control socket: the commands it sends, and the input it holds, are its own.
struct Connection: Hashable, Sendable {
    let id: UUID
    let remote: Pairing.Remote.ID
}

/// Serves the Remote and its WebSocket on loopback; `tailscale serve` adds HTTPS and the tailnet.
struct Server: Sendable {
    let remoteDirectory: String
    let port: Int
    /// Runs one command. The socket reads its next frame only once this returns, so a Remote that sends
    /// faster than the Mac keeps up waits in its own socket (and merges its motion) rather than in a queue.
    let onCommand: @Sendable (Connection, Command) async -> Void
    let clients: Clients
    let pairings: PairingStore
    /// Called with true when a Remote connects (after it can receive broadcasts) and false when it leaves.
    let onRemote: @Sendable (Connection, Bool) async -> Void
    /// Where the Phone Mic's samples go, straight from the network.
    let mic: MicFeed
    /// Called with a Phone Mic stream and its sample rate when it starts, and nil when it ends.
    let onMic: @Sendable (UUID, Double?) async -> Void

    /// The app's close code for a Remote that isn't (or is no longer) paired; the Remote shows Pairing.
    static let unpairedCloseCode: WebSocketErrorCode = .unknown(4401)

    func run() async throws {
        let onCommand = onCommand
        let clients = clients
        let pairings = pairings
        let onRemote = onRemote
        let mic = mic
        let onMic = onMic

        let router = Router()
        // no-cache: the phone checks each file (ETag) every launch, so a new Remote is never stuck in its cache.
        router.add(middleware: FileMiddleware(
            remoteDirectory, cacheControl: CacheControl([(MediaType(type: .any), [.noCache])]), searchForIndexHtml: true))

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
            await Self.shouldUpgrade(request, pairings)
        } onUpgrade: { inbound, outbound, context in
            guard let remote = try await Self.pairedRemote(context.request, pairings, outbound) else { return }
            let (outbox, continuation) = AsyncStream.makeStream(of: Outgoing.self)
            let id = await clients.add(continuation, remote: remote.id)
            guard try await Self.stillPaired(remote, pairings, clients, id, outbound) else { return }
            let connection = Connection(id: id, remote: remote.id)
            await onRemote(connection, true)
            defer { Task { await clients.remove(id); await onRemote(connection, false) } }

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
                    await onCommand(connection, command)
                }
                group.cancelAll()
            }
        }

        // The Phone Mic: binary frames of 16-bit mono PCM at `?rate=`, on a socket of its own so audio
        // never holds up commands.
        wsRouter.ws("/mic") { request, _ in
            await Self.shouldUpgrade(request, pairings)
        } onUpgrade: { inbound, outbound, context in
            guard let remote = try await Self.pairedRemote(context.request, pairings, outbound) else { return }
            guard let rate = MicStream.rate(query: context.request.uri.query) else {
                try await outbound.close(.unacceptableData, reason: "rate")
                return
            }
            let (outbox, continuation) = AsyncStream.makeStream(of: Outgoing.self)
            let id = await clients.add(continuation, remote: remote.id, kind: .mic)
            guard try await Self.stillPaired(remote, pairings, clients, id, outbound) else { return }
            mic.begin(id, rate: rate)
            await onMic(id, rate)
            defer {
                Task {
                    await clients.remove(id)
                    if mic.end(id) { await onMic(id, nil) }
                }
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await case .unpaired in outbox {
                        try await outbound.close(Self.unpairedCloseCode, reason: "notPaired")
                        return
                    }
                }
                for try await message in inbound.messages(maxSize: 1 << 16) {
                    guard case let .binary(buffer) = message else { continue }
                    mic.write(id, MicStream.samples(buffer.readableBytesView))
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

    /// A browser can't read a refused handshake's status, so every Remote is let in and the unpaired
    /// ones are closed with 4401 by `pairedRemote`. A paired Remote's cookie is sent again so it never expires.
    private static func shouldUpgrade(_ request: Request, _ pairings: PairingStore) async -> RouterShouldUpgrade {
        guard case let .paired(_, cookie) = await pairings.check(facts(request)) else { return .upgrade([:]) }
        return .upgrade([.setCookie: cookie])
    }

    /// The paired Remote on an upgraded socket, or nil after closing the socket with 4401.
    private static func pairedRemote(_ request: Request, _ pairings: PairingStore,
                                     _ outbound: WebSocketOutboundWriter) async throws -> Pairing.Remote? {
        switch await pairings.check(facts(request)) {
        case let .paired(remote, _):
            return remote
        case let .refused(refusal):
            try await outbound.close(unpairedCloseCode, reason: "\(refusal)")
            return nil
        }
    }

    /// Whether `remote` is still paired now that its socket can hear a revocation. One revoked between
    /// `pairedRemote` and joining `clients` missed the revocation's broadcast, so it's closed here instead.
    private static func stillPaired(_ remote: Pairing.Remote, _ pairings: PairingStore, _ clients: Clients,
                                    _ id: UUID, _ outbound: WebSocketOutboundWriter) async throws -> Bool {
        guard await !pairings.isPaired(remote.id) else { return true }
        await clients.remove(id)
        try await outbound.close(unpairedCloseCode, reason: "notPaired")
        return false
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
