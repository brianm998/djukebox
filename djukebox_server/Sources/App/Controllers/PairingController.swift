import Vapor
import DJukeboxCommon

// MARK: - wire types

struct PairRequestBody: Content { let name: String }
struct PairRequestResponse: Content { let requestId: String }
struct PairStatusResponse: Content { let state: String }
struct PairIdBody: Content { let requestId: String }
struct PairApproveResponse: Content { let code: String }
struct PairClaimBody: Content { let requestId: String; let code: String }

// A single response shape for /pair/claim. `outcome` is one of:
// "paired" | "wrongCode" | "notApproved" | "denied" | "unknown". The token is
// present only when paired. Returning a 200 with an outcome (rather than mapping
// each case onto an HTTP status) keeps the new device's parsing unambiguous.
struct PairClaimResponse: Content {
    let outcome: String
    let token: String?
}

/*
 The device-pairing handshake. See PairingService for the state it drives.

 Request/status/claim are reachable WITHOUT auth — the new device has no token
 yet. Pending/approve/deny require auth (loopback or an already-paired token), so
 only a trusted client can see and approve incoming requests.
 */
func pairingRoutes(_ app: Application) throws {

    // Step 1 (new device): announce an intent to pair.
    // curl -d '{"name":"Brian iPhone"}' -H 'content-type: application/json' localhost:8080/pair/request
    app.post("pair", "request") { req -> PairRequestResponse in
        let body = try req.content.decode(PairRequestBody.self)
        return PairRequestResponse(requestId: pairingService.createRequest(name: body.name))
    }

    // New device polls this to know when to prompt for the code (or that it was denied).
    // curl localhost:8080/pair/status/<requestId>
    app.get("pair", "status", ":requestId") { req -> PairStatusResponse in
        guard let id = req.parameters.get("requestId"),
              let state = pairingService.status(id: id)
        else { throw Abort(.notFound) }
        return PairStatusResponse(state: state.rawValue)
    }

    // Step 5 (trusted client): the requests waiting for approval.
    app.get("pair", "pending") { req -> [PairingService.PendingInfo] in
        let auth = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try auth.headerAuth(request: req) { pairingService.pending() }
    }

    // Step 6/7 (trusted client): approve a request and get the code to read aloud.
    app.post("pair", "approve") { req -> PairApproveResponse in
        let auth = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try auth.headerAuth(request: req) {
            let body = try req.content.decode(PairIdBody.self)
            guard let code = pairingService.approve(id: body.requestId) else {
                throw Abort(.notFound)
            }
            return PairApproveResponse(code: code)
        }
    }

    // Step 6 (trusted client): reject a request.
    app.post("pair", "deny") { req -> Response in
        let auth = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try auth.headerAuth(request: req) {
            let body = try req.content.decode(PairIdBody.self)
            return pairingService.deny(id: body.requestId) ? Response(status: .ok)
                                                            : Response(status: .notFound)
        }
    }

    // Step 8/9 (new device): exchange the approved code for a permanent token.
    app.post("pair", "claim") { req -> PairClaimResponse in
        let body = try req.content.decode(PairClaimBody.self)
        switch pairingService.claim(id: body.requestId, code: body.code) {
        case .paired(let token): return PairClaimResponse(outcome: "paired", token: token)
        case .wrongCode:         return PairClaimResponse(outcome: "wrongCode", token: nil)
        case .notApproved:       return PairClaimResponse(outcome: "notApproved", token: nil)
        case .denied:            return PairClaimResponse(outcome: "denied", token: nil)
        case .unknownRequest:    return PairClaimResponse(outcome: "unknown", token: nil)
        }
    }
}
