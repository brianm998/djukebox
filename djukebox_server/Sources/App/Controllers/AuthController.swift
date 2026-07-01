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
 */
class AuthController {
    let pairing: PairingService
    let trackFinder: TrackFinderType

    init(pairing: PairingService, trackFinder: TrackFinderType) {
        self.pairing = pairing
        self.trackFinder = trackFinder
    }

    private func isLoopback(_ req: Request) -> Bool {
        guard let ip = req.remoteAddress?.ipAddress else { return false }
        return ip == "127.0.0.1" || ip == "::1" || ip == "::ffff:127.0.0.1"
    }

    private func isAuthorized(_ req: Request, credential: String?) -> Bool {
        if isLoopback(req) { return true }
        if let credential = credential, pairing.accepts(token: credential) { return true }
        return false
    }

    // curl -H "Authorization: <token>" http://localhost:8080/rand
    func headerAuth<T>(request req: Request, closure: () throws -> T) throws -> T {
        if isAuthorized(req, credential: req.headers.first(name: "Authorization")) {
            return try closure()
        }
        throw Abort(.unauthorized)
    }

    // curl http://localhost:8080/stream/<token>/<sha1>
    func pathAuth<T>(request req: Request, closure: () async throws -> T) async throws -> T {
        if isAuthorized(req, credential: req.parameters.get("auth")) {
            return try await closure()
        }
        throw Abort(.unauthorized)
    }

    func trackFromPath<T>(from req: Request, // XXX reame this
                          closure: (AudioTrack, String) async throws -> T) async throws -> T
    {
        return try await self.pathAuth(request: req) {
            if let hash = req.parameters.get("sha1"),
               let (track, path) = trackFinder.track(forHash: hash),
               let audioTrack = track as? AudioTrack
            {
                return try await closure(audioTrack, path.path)
            } else {
                throw Abort(.notFound)
            }
        }
    }

    func track<T>(from req: Request,
                  closure: (AudioTrack, String) throws -> T) throws -> T
    {
        return try self.headerAuth(request: req) {
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
}
