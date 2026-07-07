import Vapor
import DJukeboxCommon

/*
 Gates the track/history/player routes.

 There is no longer a shared password. A request is trusted if EITHER:

  - it arrives over loopback (127.0.0.1 / ::1) — i.e. a client running on the same
    machine as the daemon, which never has to pair; or
  - it presents a bearer token belonging to a device that has completed pairing
    (the `Authorization` header for most routes, the `:auth` path segment for the
    streaming route).

 Loopback is judged from the real TCP peer (`req.remoteAddress`), which Vapor does
 not derive from forwarding headers, so it can't be spoofed by a remote client.

 The actual gate lives in `AuthMiddleware` below, applied to a protected route
 group (`let protected = app.grouped(AuthMiddleware(...))`) in routes.swift's
 top-level `routes(_:)`. `AuthController` now only holds the track-resolution
 helpers (`track`/`trackFromPath`), which do more than auth —
 they also resolve `:sha1` into an `AudioTrack` — so they stay available to
 handlers that need that resolution, but no longer perform the auth check
 themselves; the group's middleware has already gated the request by the time a
 handler runs.
 */

// Loopback-or-token check, shared by AuthMiddleware and (for the WebSocket
// upgrade, which can't throw into a normal HTTP error the same way) the
// `/stream` route's own non-throwing check.
func isLoopback(_ req: Request) -> Bool {
    guard let ip = req.remoteAddress?.ipAddress else { return false }
    return ip == "127.0.0.1" || ip == "::1" || ip == "::ffff:127.0.0.1"
}

func isAuthorized(_ req: Request, credential: String?, pairing: PairingService) -> Bool {
    if isLoopback(req) { return true }
    if let credential, pairing.accepts(token: credential) { return true }
    return false
}

// Applied to a protected route group (`app.grouped(AuthMiddleware(pairing:))`)
// covering every route that used to open with `AuthController(...).headerAuth`.
// Accepts EITHER the `Authorization` header (used by almost every protected
// route) OR an `auth` path parameter (used only by `/stream/:auth/:sha1`, whose
// auth token travels in the URL rather than a header) — checking both means the
// same middleware/group can protect that route too, rather than needing a
// special-cased carve-out.
struct AuthMiddleware: AsyncMiddleware {
    let pairing: PairingService

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let credential = req.headers.first(name: "Authorization") ?? req.parameters.get("auth")
        guard isAuthorized(req, credential: credential, pairing: pairing) else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: req)
    }
}

class AuthController {
    let pairing: PairingService
    let trackFinder: TrackFinderType

    init(pairing: PairingService, trackFinder: TrackFinderType) {
        self.pairing = pairing
        self.trackFinder = trackFinder
    }

    // Non-throwing header auth for the WebSocket upgrade, which can't use the
    // AsyncMiddleware form directly for its own belt-and-suspenders check (the
    // route itself is now also gated by AuthMiddleware on the protected group;
    // this stays as a defensive second check right at the upgrade closure,
    // matching the pre-existing behavior of closing rather than throwing there).
    func authorizes(_ req: Request) -> Bool {
        isAuthorized(req, credential: req.headers.first(name: "Authorization"), pairing: pairing)
    }

    // Resolves `:sha1` (from the `:auth`-authed streaming route) into an
    // AudioTrack + file path. NOT an auth check — the caller must already be on
    // the protected group (AuthMiddleware checks the `auth` path param there).
    // curl http://localhost:8080/stream/<token>/<sha1>
    func trackFromPath<T>(from req: Request,
                          closure: (AudioTrack, String) async throws -> T) async throws -> T
    {
        if let hash = req.parameters.get("sha1"),
           let (track, path) = trackFinder.track(forHash: hash),
           let audioTrack = track as? AudioTrack
        {
            return try await closure(audioTrack, path.path)
        } else {
            throw Abort(.notFound)
        }
    }

    // Resolves `:sha1` into an AudioTrack + file path. NOT an auth check — the
    // caller must already be on the protected group (AuthMiddleware has already
    // gated the request via the Authorization header by the time this runs).
    func track<T>(from req: Request,
                  closure: (AudioTrack, String) throws -> T) throws -> T
    {
        if let hash = req.parameters.get("sha1"),
           let (track, path) = trackFinder.track(forHash: hash),
           let audioTrack = track as? AudioTrack
        {
            return try closure(audioTrack, path.path)
        } else {
            throw Abort(.notFound)
        }
    }
}
