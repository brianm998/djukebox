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

    // In-memory testing has no remote address, so the request is not trusted as
    // loopback and carries no token: it only succeeds if /version needs no auth.
    func testVersionEndpoint() async throws {
        let app = try await Application.make(.testing)
        try configure(app)

        try await app.testable().test(.GET, "version") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let info = try res.content.decode(VersionInfo.self)
            XCTAssertEqual(info.name, "DJukebox")
            XCTAssertEqual(info.version, DJukeboxVersion.current)
        }
        // the control for the above: a protected route refuses the same caller
        try await app.testable().test(.GET, "queue") { res async in
            XCTAssertEqual(res.status, .unauthorized)
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

    func testMusicDirCheck() throws {
        let tmp = NSTemporaryDirectory() + "mdcheck-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmp) }

        XCTAssertThrowsError(try checkMusicDirectory(tmp + "/missing"))

        let file = tmp + "/file"
        fm.createFile(atPath: file, contents: Data())
        XCTAssertThrowsError(try checkMusicDirectory(file))

        let empty = tmp + "/empty"
        try fm.createDirectory(atPath: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try checkMusicDirectory(empty))

        XCTAssertNoThrow(try checkMusicDirectory(tmp))
    }
}
