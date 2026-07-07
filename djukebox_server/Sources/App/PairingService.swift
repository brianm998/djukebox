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

 These two responsibilities are split across two different synchronization
 mechanisms, because they have different callers:

  - `accepts(token:)` is called from AuthController's `isAuthorized`, which is in
    turn called from three SYNCHRONOUS, non-async helpers (`headerAuth`, used by
    ~28 routes; `authorizes`, used by the synchronous WebSocket upgrade closure;
    and `track`). None of those can easily become `async`, so `accepts(token:)`
    must stay a plain synchronous method. Its state (`validTokenHashes`) is
    guarded by a plain lock (`NSLock`, the idiom already used for this kind of
    small in-RAM guarded state elsewhere in this directory — see
    TrackFinder.swift and History.swift).

  - The pending-request table (`requests`) is only touched from PairingController's
    route closures, which are already `async throws`. That table is modeled as a
    private nested `actor` so its methods can be `await`ed cleanly instead of
    going through a DispatchQueue.

 `PairingService` itself stays a plain (non-actor) class so `accepts(token:)` can
 remain synchronous; it forwards the pairing-flow methods to the nested actor.
 */
// @unchecked Sendable: `validTokenHashes` is guarded by `tokenLock`; the pending
// request table lives in `RequestTable`, an actor, which is safe to share as-is.
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

    /// Internal variant of `ClaimResult` that also carries the new token's hash,
    /// so the caller can add it to `validTokenHashes` without re-hashing.
    private enum InternalClaimResult {
        case paired(token: String, hash: String)
        case wrongCode
        case notApproved
        case denied
        case unknownRequest
    }

    /// What /pair/pending exposes to trusted clients.
    public struct PendingInfo: Content {
        public let requestId: String
        public let name: String
        public let createdAt: Double
    }

    private let database: JukeboxDatabase

    // MARK: - token check (sync hot path)

    // Guards the set of accepted token hashes. Plain NSLock (not an actor) so
    // `accepts(token:)` stays synchronous and callable from AuthController's
    // existing non-async call sites with zero changes to their signatures.
    private let tokenLock = NSLock()
    private var validTokenHashes: Set<String>

    private func withTokenLock<T>(_ body: () -> T) -> T {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return body()
    }

    /// Whether the token presented by a client matches a paired device. The caller
    /// passes the raw token; we hash it here and compare against the stored hashes.
    public func accepts(token: String) -> Bool {
        let hash = Self.hash(token)
        return withTokenLock { validTokenHashes.contains(hash) }
    }

    // MARK: - pending-request table (async pairing flow)

    /// Owns the pending-request table. Isolated as an actor because every caller
    /// (PairingController's route closures) is already async and can `await` it.
    private actor RequestTable {
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

        private var requests: [String: Request] = [:]

        /// Step 1 (new device): register an intent to pair. Returns the request id
        /// the device polls and later claims with. Drops the oldest expired
        /// entries first.
        func createRequest(name: String) -> String {
            pruneExpired()
            // if we're somehow flooded with live requests, refuse rather than grow
            if requests.count >= PairingService.maxPendingRequests {
                Log.w("pairing: too many pending requests, dropping the oldest")
                if let oldest = requests.values.min(by: { $0.createdAt < $1.createdAt }) {
                    requests[oldest.id] = nil
                }
            }
            let id = PairingService.randomHex(bytes: 16)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            requests[id] = Request(id: id,
                                   name: trimmed.isEmpty ? "Unknown device" : trimmed,
                                   createdAt: Date().timeIntervalSince1970)
            Log.i("pairing: new request \(id) from \(trimmed)")
            return id
        }

        /// Step 5 (trusted client): the list of requests still waiting to be approved.
        func pending() -> [PendingInfo] {
            pruneExpired()
            return requests.values
              .filter { $0.state == .requested }
              .sorted { $0.createdAt < $1.createdAt }
              .map { PendingInfo(requestId: $0.id, name: $0.name, createdAt: $0.createdAt) }
        }

        /// Step 6/7 (trusted client): approve a request and mint the 6-digit code
        /// that the user reads off this device and types into the new one.
        func approve(id: String) -> String? {
            pruneExpired()
            guard let request = requests[id] else { return nil }
            // re-approving returns the same code so a double-tap doesn't rotate it
            if request.state == .approved, let code = request.code { return code }
            let code = PairingService.randomCode()
            request.state = .approved
            request.code = code
            Log.i("pairing: approved \(id)")
            return code
        }

        /// Step 6 (trusted client): reject a request.
        func deny(id: String) -> Bool {
            pruneExpired()
            guard let request = requests[id] else { return false }
            request.state = .denied
            request.code = nil
            Log.i("pairing: denied \(id)")
            return true
        }

        /// What the new device polls so it can show "waiting / enter the code / rejected".
        func status(id: String) -> State? {
            pruneExpired()
            return requests[id]?.state
        }

        /// Step 8/9 (new device): exchange the approved code for a permanent
        /// token. On success the token hash is persisted; the pairing service
        /// caller adds it to the live `validTokenHashes` set (this actor does not
        /// touch that lock-guarded state itself). The request is consumed. The
        /// raw token is returned exactly once here and never stored.
        func claim(id: String, code: String, database: JukeboxDatabase) -> PairingService.InternalClaimResult {
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
                    if request.attempts >= PairingService.maxClaimAttempts {
                        Log.w("pairing: \(id) burned after \(request.attempts) bad codes")
                        requests[id] = nil
                    }
                    return .wrongCode
                }
                let token = PairingService.randomHex(bytes: 32)
                let hash = PairingService.hash(token)
                do {
                    try database.addPairedClient(name: request.name, tokenHash: hash,
                                                 at: Date().timeIntervalSince1970)
                } catch {
                    Log.e("pairing: could not persist paired client: \(error)")
                    // don't hand out a token we failed to remember
                    return .unknownRequest
                }
                requests[id] = nil
                Log.i("pairing: \(id) (\(request.name)) paired")
                return .paired(token: token, hash: hash)
            }
        }

        /// Drops requests older than the TTL.
        private func pruneExpired() {
            let cutoff = Date().timeIntervalSince1970 - PairingService.requestTTL
            for (id, request) in requests where request.createdAt < cutoff {
                requests[id] = nil
            }
        }
    }

    private let requestTable = RequestTable()

    public init(database: JukeboxDatabase, tokenHashes: Set<String>) {
        self.database = database
        self.validTokenHashes = tokenHashes
    }

    // MARK: - pairing flow (forwards to the actor-isolated request table)

    public func createRequest(name: String) async -> String {
        await requestTable.createRequest(name: name)
    }

    public func pending() async -> [PendingInfo] {
        await requestTable.pending()
    }

    public func approve(id: String) async -> String? {
        await requestTable.approve(id: id)
    }

    public func deny(id: String) async -> Bool {
        await requestTable.deny(id: id)
    }

    public func status(id: String) async -> State? {
        await requestTable.status(id: id)
    }

    /// Step 8/9 (new device): exchange the approved code for a permanent token.
    /// On success the token hash is added to the live, lock-guarded set that
    /// `accepts(token:)` reads synchronously.
    public func claim(id: String, code: String) async -> ClaimResult {
        switch await requestTable.claim(id: id, code: code, database: database) {
        case .paired(let token, let hash):
            withTokenLock { _ = validTokenHashes.insert(hash) }
            return .paired(token: token)
        case .wrongCode:      return .wrongCode
        case .notApproved:    return .notApproved
        case .denied:         return .denied
        case .unknownRequest: return .unknownRequest
        }
    }

    // MARK: - helpers

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).hexEncodedString()
    }

    private static func randomHex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.hexEncodedString()
    }

    /// A zero-padded 6-digit code, shown to the user grouped as "NNN NNN".
    private static func randomCode() -> String {
        let digits = String(UInt32.random(in: 0...999_999))
        return String(repeating: "0", count: 6 - digits.count) + digits
    }
}
