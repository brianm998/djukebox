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
 yet — so they're registered on `app` directly. Pending/approve/deny require auth
 (loopback or an already-paired token), so only a trusted client can see and
 approve incoming requests; those three are registered on `protected`
 (`app.grouped(AuthMiddleware(...))`, built in routes.swift) instead, and no
 longer perform their own auth check — AuthMiddleware has already gated the
 request by the time these closures run.
 */
func pairingRoutes(_ app: Application, protected: any RoutesBuilder) throws {

    // Step 1 (new device): announce an intent to pair.
    // curl -d '{"name":"Brian iPhone"}' -H 'content-type: application/json' localhost:8080/pair/request
    app.post("pair", "request") { req async throws -> PairRequestResponse in
        let body = try req.content.decode(PairRequestBody.self)
        return PairRequestResponse(requestId: await pairingService.createRequest(name: body.name))
    }

    // New device polls this to know when to prompt for the code (or that it was denied).
    // curl localhost:8080/pair/status/<requestId>
    app.get("pair", "status", ":requestId") { req async throws -> PairStatusResponse in
        guard let id = req.parameters.get("requestId"),
              let state = await pairingService.status(id: id)
        else { throw Abort(.notFound) }
        return PairStatusResponse(state: state.rawValue)
    }

    // Step 5 (trusted client): the requests waiting for approval.
    protected.get("pair", "pending") { req async throws -> [PairingService.PendingInfo] in
        return await pairingService.pending()
    }

    // Step 6/7 (trusted client): approve a request and get the code to read aloud.
    protected.post("pair", "approve") { req async throws -> PairApproveResponse in
        let body = try req.content.decode(PairIdBody.self)
        guard let code = await pairingService.approve(id: body.requestId) else {
            throw Abort(.notFound)
        }
        return PairApproveResponse(code: code)
    }

    // Step 6 (trusted client): reject a request.
    protected.post("pair", "deny") { req async throws -> Response in
        let body = try req.content.decode(PairIdBody.self)
        return await pairingService.deny(id: body.requestId) ? Response(status: .ok)
                                                              : Response(status: .notFound)
    }

    // Step 8/9 (new device): exchange the approved code for a permanent token.
    app.post("pair", "claim") { req async throws -> PairClaimResponse in
        let body = try req.content.decode(PairClaimBody.self)
        switch await pairingService.claim(id: body.requestId, code: body.code) {
        case .paired(let token): return PairClaimResponse(outcome: "paired", token: token)
        case .wrongCode:         return PairClaimResponse(outcome: "wrongCode", token: nil)
        case .notApproved:       return PairClaimResponse(outcome: "notApproved", token: nil)
        case .denied:            return PairClaimResponse(outcome: "denied", token: nil)
        case .unknownRequest:    return PairClaimResponse(outcome: "unknown", token: nil)
        }
    }
}
