@testable import App
import XCTVapor
import DJukeboxCommon

final class AppTests: XCTestCase {
    // Real routes, exercised over a real loopback TCP connection so
    // AuthController's isLoopback() check (which reads req.remoteAddress) sees
    // a genuine peer address rather than the nil address in-memory testing uses.
    func testQueueOverLoopback() async throws {
        let app = try await Application.make(.testing)
        try configure(app)

        let tester = try app.testable(method: .running(hostname: "127.0.0.1", port: 0))
        try await tester.test(.GET, "queue") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNoThrow(try res.content.decode(PlayingQueue.self))
        }

        try await app.asyncShutdown()
    }

    func testPairingRoundTrip() async throws {
        let app = try await Application.make(.testing)
        try configure(app)

        let tester = try app.testable(method: .running(hostname: "127.0.0.1", port: 0))

        var requestId = ""
        try await tester.test(.POST, "pair/request", beforeRequest: { req in
            try req.content.encode(PairRequestBody(name: "Test Device"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            requestId = try res.content.decode(PairRequestResponse.self).requestId
        })
        XCTAssertFalse(requestId.isEmpty)

        // approve requires auth; this connects over real loopback, so it's trusted.
        var code = ""
        try await tester.test(.POST, "pair/approve", beforeRequest: { req in
            try req.content.encode(PairIdBody(requestId: requestId))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            code = try res.content.decode(PairApproveResponse.self).code
        })
        XCTAssertFalse(code.isEmpty)

        try await tester.test(.POST, "pair/claim", beforeRequest: { req in
            try req.content.encode(PairClaimBody(requestId: requestId, code: code))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let claim = try res.content.decode(PairClaimResponse.self)
            XCTAssertEqual(claim.outcome, "paired")
            XCTAssertNotNil(claim.token)
        })

        try await app.asyncShutdown()
    }
}
