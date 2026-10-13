import Foundation
import HostCore

/// The Host's Pairing, saved to `~/Library/Application Support/MyRemote/remotes.json` after every change.
@MainActor @Observable
final class PairingStore {
    private(set) var pairing: Pairing
    /// The Remote the live code just paired, for the pairing window to confirm.
    private(set) var justPaired: String?
    /// Why the last code stopped working early (too many wrong tries), for the pairing window.
    private(set) var codeDied = false
    private(set) var saveError: String?
    /// A revocation the file doesn't have yet: it holds while the Host runs, but restarting now would
    /// bring the Remote back. Every later save tries again.
    private(set) var unsavedRevocation = false

    private let file: URL

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "MyRemote", directoryHint: .isDirectory)
        file = directory.appending(path: "remotes.json")
        // A missing or unreadable file means no Remote is paired; they pair again.
        pairing = (try? Data(contentsOf: file)).flatMap { try? Pairing(saved: $0) } ?? Pairing()
    }

    var remotes: [Pairing.Remote] { pairing.remotes }
    var code: Pairing.Code? { pairing.code }

    func newCode() {
        _ = pairing.newCode(now: .now)
        justPaired = nil
        codeDied = false
    }

    func cancelCode() {
        pairing.cancelCode()
    }

    func pair(_ request: Pairing.Request, code: String) -> Pairing.Decision {
        let decision = pairing.pair(request, code: code, now: .now)
        switch decision {
        case let .paired(remote, _):
            justPaired = remote.name
            save()
        case .refused(.tooManyTries):
            codeDied = true
        case .refused:
            break
        }
        return decision
    }

    /// Checked once per connection, so saving the new last-seen each time costs little.
    func check(_ request: Pairing.Request) -> Pairing.Decision {
        let decision = pairing.check(request, now: .now)
        if case .paired = decision { save() }
        return decision
    }

    func isPaired(_ id: Pairing.Remote.ID) -> Bool {
        pairing.remotes.contains { $0.id == id }
    }

    func unpair(_ request: Pairing.Request) -> Pairing.Remote? {
        let remote = pairing.unpair(request)
        if remote != nil { saveRevocation() }
        return remote
    }

    func revoke(_ id: Pairing.Remote.ID) {
        pairing.revoke(id)
        saveRevocation()
    }

    func revokeAll() {
        pairing.revokeAll()
        saveRevocation()
    }

    private func saveRevocation() {
        if !save() { unsavedRevocation = true }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try pairing.saved().write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
            saveError = nil
            unsavedRevocation = false
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
