import CryptoKit
import Foundation

/// Which Remotes may control the Host: the live Pairing code, and every paired Remote.
public struct Pairing: Sendable {
    /// What the Host needs from an HTTP request to decide on it.
    public struct Request: Sendable {
        public var cookie: String?
        public var login: String?
        public var origin: String?
        public var host: String?
        public var userAgent: String?

        public init(cookie: String?, login: String?, origin: String?, host: String?, userAgent: String?) {
            self.cookie = cookie
            self.login = login
            self.origin = origin
            self.host = host
            self.userAgent = userAgent
        }
    }

    public struct Code: Equatable, Sendable {
        public var digits: String
        public var expires: Date
    }

    public struct Remote: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var pairedAt: Date
        public var lastSeen: Date
        /// The `Tailscale-User-Login` it paired under; every later request must carry the same.
        var login: String
        /// SHA-256 of its token, hex; the token itself lives only in the Remote's cookie.
        var tokenHash: String
    }

    public enum Decision: Equatable, Sendable {
        /// `cookie` is the `Set-Cookie` value that hands the Remote its token, sent again on every connection
        /// so a Remote in use never expires.
        case paired(Remote, cookie: String)
        case refused(Refusal)
    }

    /// Why the Host turned a request away.
    public enum Refusal: Error, Equatable, Sendable {
        /// No `Tailscale-User-Login`: Funnel, a tagged device, or something on the Mac skipping `tailscale serve`.
        case notOnTailnet
        /// The request didn't come from a page the Host served at that address.
        case otherOrigin
        /// No cookie, or a token the Host never issued or has revoked.
        case notPaired
        /// A paired Remote's token under another tailnet login than the one it paired with.
        case otherLogin
        /// No code is live: none was asked for, it expired, it was used, or it died.
        case noCode
        case wrongCode
        /// That was the last wrong try; the code is dead.
        case tooManyTries
    }

    public private(set) var remotes: [Remote] = []
    public private(set) var code: Code?
    private var wrongTries = 0

    static let codeLifetime: TimeInterval = 120
    static let triesPerCode = 5
    static let cookieName = "myremote"
    /// The longest browsers keep a cookie.
    static let cookieMaxAge = 400 * 24 * 60 * 60

    public init() {}

    /// The paired Remotes from `saved()`; a live code doesn't survive.
    public init(saved: Data) throws {
        remotes = try Self.decoder.decode(Saved.self, from: saved).remotes
    }

    /// The paired Remotes as JSON, for `remotes.json`.
    public func saved() -> Data {
        // Encoding plain strings, dates and UUIDs can't fail.
        try! Self.encoder.encode(Saved(remotes: remotes))
    }

    private struct Saved: Codable {
        var remotes: [Remote]
    }

    private static let encoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public mutating func newCode(now: Date) -> Code {
        let code = Code(digits: String(format: "%06d", Int.random(in: 0..<1_000_000)), expires: now + Self.codeLifetime)
        self.code = code
        wrongTries = 0
        return code
    }

    public mutating func cancelCode() {
        code = nil
    }

    public mutating func pair(_ request: Request, code digits: String, now: Date) -> Decision {
        if let refusal = Self.refusal(of: request) { return .refused(refusal) }
        guard let code, now <= code.expires else {
            self.code = nil
            return .refused(.noCode)
        }
        guard digits == code.digits else {
            wrongTries += 1
            guard wrongTries >= Self.triesPerCode else { return .refused(.wrongCode) }
            self.code = nil
            return .refused(.tooManyTries)
        }
        self.code = nil
        let token = Self.newToken()
        let name = Self.name(userAgent: request.userAgent ?? "", taken: Set(remotes.map(\.name)))
        let remote = Remote(id: UUID(), name: name, pairedAt: now, lastSeen: now,
                            login: request.login ?? "", tokenHash: Self.hash(token))
        remotes.append(remote)
        return .paired(remote, cookie: Self.setCookie(token))
    }

    /// Whether a request comes from a paired Remote.
    public mutating func check(_ request: Request, now: Date) -> Decision {
        switch find(request) {
        case let .failure(refusal):
            return .refused(refusal)
        case let .success((index, token)):
            remotes[index].lastSeen = now
            return .paired(remotes[index], cookie: Self.setCookie(token))
        }
    }

    public mutating func revoke(_ id: Remote.ID) {
        remotes.removeAll { $0.id == id }
    }

    public mutating func revokeAll() {
        remotes.removeAll()
    }

    /// Revokes the Remote making the request, which then gets `clearedCookie`; nil if it isn't a paired Remote.
    public mutating func unpair(_ request: Request) -> Remote? {
        guard case let .success((index, _)) = find(request) else { return nil }
        return remotes.remove(at: index)
    }

    /// The `Set-Cookie` value that deletes the token from the Remote.
    public static let clearedCookie = "\(cookieName)=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0"

    /// What the menu calls a new Remote: its kind of device, numbered if that name is taken.
    public static func name(userAgent: String, taken: Set<String>) -> String {
        let kind = switch userAgent {
        case let ua where ua.contains("iPhone"): "iPhone"
        case let ua where ua.contains("iPad"): "iPad"
        case let ua where ua.contains("Android"): "Android"
        case let ua where ua.contains("Macintosh"): "Mac or iPad"
        default: "Browser"
        }
        var name = kind
        var number = 1
        while taken.contains(name) {
            number += 1
            name = "\(kind) \(number)"
        }
        return name
    }

    /// The paired Remote a request comes from, and its token.
    private func find(_ request: Request) -> Result<(Int, String), Refusal> {
        if let refusal = Self.refusal(of: request) { return .failure(refusal) }
        guard let token = Self.token(in: request.cookie),
              let index = remotes.firstIndex(where: { $0.tokenHash == Self.hash(token) })
        else { return .failure(.notPaired) }
        guard remotes[index].login == request.login else { return .failure(.otherLogin) }
        return .success((index, token))
    }

    private static func newToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func setCookie(_ token: String) -> String {
        "\(cookieName)=\(token); HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=\(cookieMaxAge)"
    }

    /// The Host's token among the `Cookie` header's pairs.
    private static func token(in cookieHeader: String?) -> String? {
        for pair in (cookieHeader ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == cookieName {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The checks every request must pass before its token or code counts.
    private static func refusal(of request: Request) -> Refusal? {
        guard let login = request.login, !login.isEmpty else { return .notOnTailnet }
        guard let host = request.host, let origin = request.origin,
              origin.caseInsensitiveCompare("https://" + host) == .orderedSame
        else { return .otherOrigin }
        return nil
    }
}
