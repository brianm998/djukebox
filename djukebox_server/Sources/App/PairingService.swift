import Foundation
import Vapor
import Crypto
import DJukeboxCommon

/*
 Holds all pairing state for the server.

 Two responsibilities:

 1. The set of token hashes that identify already-paired devices. Seeded from the
    database at startup and consulted on every authenticated request, so it lives
    in RAM (a single Set lookup) rather than hitting the database per request.

 2. The short-lived, in-memory table of *pending* pairing requests. A device on
    the WiFi with no token POSTs /pair/request; an already-trusted client polls
    /pair/pending, approves it (which mints a 6-digit code), reads the code aloud,
    and the new device claims a permanent token with that code.

 All state is guarded by one serial queue so it is safe to touch from any
 event-loop thread.
 */
// @unchecked Sendable: every access to the mutable token set and request table
// is funnelled through the serial `queue` (see the type doc above).
public final class PairingService: @unchecked Sendable {

    // how long a pending request (and its code) stays valid
    private static let requestTTL: TimeInterval = 5 * 60
    // most failed code guesses before a request is burned
    private static let maxClaimAttempts = 5
    // cap on concurrent pending requests (the request endpoint is unauthenticated)
    private static let maxPendingRequests = 20

    public enum State: String, Content {
        case requested      // waiting for a trusted client to approve
        case approved       // approved; a code has been issued
        case denied         // a trusted client rejected it
    }

    /// The outcome of a /pair/claim attempt.
    public enum ClaimResult {
        case paired(token: String)
        case wrongCode
        case notApproved        // still waiting for approval
        case denied
        case unknownRequest     // never existed, already consumed, or expired
    }

    /// What /pair/pending exposes to trusted clients.
    public struct PendingInfo: Content {
        public let requestId: String
        public let name: String
        public let createdAt: Double
    }

    private final class Request {
        let id: String
        let name: String
        let createdAt: Double
        var state: State
        var code: String?
        var attempts: Int

        init(id: String, name: String, createdAt: Double) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.state = .requested
            self.code = nil
            self.attempts = 0
        }
    }

    private let queue = DispatchQueue(label: "djukebox-pairing")
    private let database: JukeboxDatabase
    private var validTokenHashes: Set<String>
    private var requests: [String: Request] = [:]

    public init(database: JukeboxDatabase, tokenHashes: Set<String>) {
        self.database = database
        self.validTokenHashes = tokenHashes
    }

    // MARK: - auth

    /// Whether the token presented by a client matches a paired device. The caller
    /// passes the raw token; we hash it here and compare against the stored hashes.
    public func accepts(token: String) -> Bool {
        let hash = Self.hash(token)
        return queue.sync { validTokenHashes.contains(hash) }
    }

    // MARK: - pairing flow

    /// Step 1 (new device): register an intent to pair. Returns the request id the
    /// device polls and later claims with. Drops the oldest expired entries first.
    public func createRequest(name: String) -> String {
        queue.sync {
            pruneExpired()
            // if we're somehow flooded with live requests, refuse rather than grow
            if requests.count >= Self.maxPendingRequests {
                Log.w("pairing: too many pending requests, dropping the oldest")
                if let oldest = requests.values.min(by: { $0.createdAt < $1.createdAt }) {
                    requests[oldest.id] = nil
                }
            }
            let id = Self.randomHex(bytes: 16)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            requests[id] = Request(id: id,
                                   name: trimmed.isEmpty ? "Unknown device" : trimmed,
                                   createdAt: Date().timeIntervalSince1970)
            Log.i("pairing: new request \(id) from \(trimmed)")
            return id
        }
    }

    /// Step 5 (trusted client): the list of requests still waiting to be approved.
    public func pending() -> [PendingInfo] {
        queue.sync {
            pruneExpired()
            return requests.values
              .filter { $0.state == .requested }
              .sorted { $0.createdAt < $1.createdAt }
              .map { PendingInfo(requestId: $0.id, name: $0.name, createdAt: $0.createdAt) }
        }
    }

    /// Step 6/7 (trusted client): approve a request and mint the 6-digit code that
    /// the user reads off this device and types into the new one.
    public func approve(id: String) -> String? {
        queue.sync {
            pruneExpired()
            guard let request = requests[id] else { return nil }
            // re-approving returns the same code so a double-tap doesn't rotate it
            if request.state == .approved, let code = request.code { return code }
            let code = Self.randomCode()
            request.state = .approved
            request.code = code
            Log.i("pairing: approved \(id)")
            return code
        }
    }

    /// Step 6 (trusted client): reject a request.
    public func deny(id: String) -> Bool {
        queue.sync {
            pruneExpired()
            guard let request = requests[id] else { return false }
            request.state = .denied
            request.code = nil
            Log.i("pairing: denied \(id)")
            return true
        }
    }

    /// What the new device polls so it can show "waiting / enter the code / rejected".
    public func status(id: String) -> State? {
        queue.sync {
            pruneExpired()
            return requests[id]?.state
        }
    }

    /// Step 8/9 (new device): exchange the approved code for a permanent token. On
    /// success the token hash is persisted and added to the live set; the request
    /// is consumed. The raw token is returned exactly once here and never stored.
    public func claim(id: String, code: String) -> ClaimResult {
        queue.sync {
            pruneExpired()
            guard let request = requests[id] else { return .unknownRequest }
            switch request.state {
            case .denied:
                requests[id] = nil
                return .denied
            case .requested:
                return .notApproved
            case .approved:
                let entered = code.filter(\.isNumber)
                guard let expected = request.code, entered == expected else {
                    request.attempts += 1
                    if request.attempts >= Self.maxClaimAttempts {
                        Log.w("pairing: \(id) burned after \(request.attempts) bad codes")
                        requests[id] = nil
                    }
                    return .wrongCode
                }
                let token = Self.randomHex(bytes: 32)
                let hash = Self.hash(token)
                do {
                    try database.addPairedClient(name: request.name, tokenHash: hash,
                                                 at: Date().timeIntervalSince1970)
                } catch {
                    Log.e("pairing: could not persist paired client: \(error)")
                    // don't hand out a token we failed to remember
                    return .unknownRequest
                }
                validTokenHashes.insert(hash)
                requests[id] = nil
                Log.i("pairing: \(id) (\(request.name)) paired")
                return .paired(token: token)
            }
        }
    }

    // MARK: - helpers (assume already on the queue where noted)

    /// Drops requests older than the TTL. Must run on `queue`.
    private func pruneExpired() {
        let cutoff = Date().timeIntervalSince1970 - Self.requestTTL
        for (id, request) in requests where request.createdAt < cutoff {
            requests[id] = nil
        }
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).hexEncodedString()
    }

    private static func randomHex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A zero-padded 6-digit code, shown to the user grouped as "NNN NNN".
    private static func randomCode() -> String {
        String(format: "%06u", UInt32.random(in: 0...999_999))
    }
}
