@testable import App
import XCTVapor
import DJukeboxCommon

// Keep every test that touches server state in this one class: its class-level
// setUp redirects the server's paths, and its tearDown deletes them.
final class AppTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestEnvironment.activate()
    }

    override class func tearDown() {
        TestEnvironment.remove()
        super.tearDown()
    }

    private let trackA = TestEnvironment.trackA
    private let trackB = TestEnvironment.trackB
    private let trackC = TestEnvironment.trackC

    // MARK: - helpers

    /// Runs `body` against a configured app whose audio player is a fake.
    /// In-memory requests have no remote address, so they are never trusted as
    /// loopback; `.loopback` makes a real TCP connection from 127.0.0.1.
    private func withApp(loopback: Bool = false,
                         _ body: (any XCTApplicationTester, FakeAudioPlayer) async throws -> Void)
      async throws
    {
        let app = try await Application.make(.testing)
        do {
            let player = FakeAudioPlayer()
            audioPlayer = player
            try configure(app)
            let tester = try app.testable(method: loopback
                                            ? .running(hostname: "127.0.0.1", port: 0)
                                            : .inMemory)
            try await body(tester, player)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func send(_ tester: any XCTApplicationTester,
                      _ method: HTTPMethod,
                      _ path: String,
                      token: String? = nil,
                      body: (any Content)? = nil) async throws -> XCTHTTPResponse
    {
        var headers = HTTPHeaders()
        if let token { headers.add(name: "Authorization", value: token) }
        var response: XCTHTTPResponse?
        try await tester.test(method, path, headers: headers, beforeRequest: { req in
            if let body { try req.content.encode(body) }
        }, afterResponse: { res async throws in
            response = res
        })
        return try XCTUnwrap(response)
    }

    private func requestPairing(_ tester: any XCTApplicationTester,
                                name: String = "Test Device") async throws -> String
    {
        let res = try await send(tester, .POST, "pair/request", body: PairRequestBody(name: name))
        XCTAssertEqual(res.status, .ok)
        return try res.content.decode(PairRequestResponse.self).requestId
    }

    private func claim(_ tester: any XCTApplicationTester,
                       _ requestId: String, code: String) async throws -> PairClaimResponse
    {
        let res = try await send(tester, .POST, "pair/claim",
                                 body: PairClaimBody(requestId: requestId, code: code))
        XCTAssertEqual(res.status, .ok)
        return try res.content.decode(PairClaimResponse.self)
    }

    /// A token for a freshly paired device. Approval goes straight to the
    /// service, standing in for an already-trusted client.
    private func pairedToken(_ tester: any XCTApplicationTester) async throws -> String {
        let requestId = try await requestPairing(tester)
        let approved = await pairingService.approve(id: requestId)
        let code = try XCTUnwrap(approved)
        let response = try await claim(tester, requestId, code: code)
        return try XCTUnwrap(response.token)
    }

    private func queuedHashes(_ response: XCTHTTPResponse) throws -> [String] {
        XCTAssertEqual(response.status, .ok)
        return try response.content.decode(PlayingQueue.self).tracks.map(\.SHA1)
    }

    /// Runs `body` with a paired token and with A, B and C queued in that order.
    private func withQueue(
      _ body: (any XCTApplicationTester, FakeAudioPlayer, String) async throws -> Void)
      async throws
    {
        try await withApp { tester, player in
            let token = try await self.pairedToken(tester)
            for hash in [self.trackA, self.trackB, self.trackC] {
                let res = try await self.send(tester, .GET, "play/\(hash)", token: token)
                XCTAssertEqual(res.status, .ok)
            }
            try await body(tester, player, token)
        }
    }

    private func history(_ tester: any XCTApplicationTester,
                         _ path: String, token: String) async throws -> PlayingHistory
    {
        let res = try await send(tester, .GET, path, token: token)
        XCTAssertEqual(res.status, .ok)
        return try res.content.decode(PlayingHistory.self)
    }

    private func decibels(_ tester: any XCTApplicationTester,
                          _ path: String, token: String) async throws -> Double
    {
        let res = try await send(tester, .GET, path, token: token)
        XCTAssertEqual(res.status, .ok)
        return try res.content.decode(MasterVolume.self).decibels
    }

    // MARK: - loopback

    // Real routes, exercised over a real loopback TCP connection so
    // AuthController's isLoopback() check (which reads req.remoteAddress) sees
    // a genuine peer address rather than the nil address in-memory testing uses.
    func testQueueOverLoopback() async throws {
        try await withApp(loopback: true) { tester, _ in
            let res = try await self.send(tester, .GET, "queue")
            XCTAssertEqual(res.status, .ok)
            XCTAssertNoThrow(try res.content.decode(PlayingQueue.self))
        }
    }

    func testPairingRoundTrip() async throws {
        try await withApp(loopback: true) { tester, _ in
            let requestId = try await self.requestPairing(tester)

            // approve requires auth; this connects over real loopback, so it's trusted.
            let res = try await self.send(tester, .POST, "pair/approve",
                                          body: PairIdBody(requestId: requestId))
            XCTAssertEqual(res.status, .ok)
            let code = try res.content.decode(PairApproveResponse.self).code
            XCTAssertFalse(code.isEmpty)

            let claim = try await self.claim(tester, requestId, code: code)
            XCTAssertEqual(claim.outcome, "paired")
            XCTAssertNotNil(claim.token)
        }
    }

    // MARK: - startup

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

    // MARK: - auth

    func testRequestWithoutTokenIsRejected() async throws {
        try await withApp { tester, player in
            for path in ["queue", "tracks", "history", "volume", "pair/pending",
                         "play/\(self.trackA)"]
            {
                let res = try await self.send(tester, .GET, path)
                XCTAssertEqual(res.status, .unauthorized, path)
            }
            XCTAssertEqual(player.trackQueue, [])
        }
    }

    func testBogusTokenIsRejected() async throws {
        try await withApp { tester, _ in
            let res = try await self.send(tester, .GET, "queue", token: "bogus")
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testPairedTokenIsAccepted() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testApproveWithoutTokenIsRejected() async throws {
        try await withApp { tester, _ in
            let requestId = try await self.requestPairing(tester)
            let res = try await self.send(tester, .POST, "pair/approve",
                                          body: PairIdBody(requestId: requestId))
            XCTAssertEqual(res.status, .unauthorized)
            let state = await pairingService.status(id: requestId)
            XCTAssertEqual(state, .requested)
        }
    }

    func testStreamPathTokenIsChecked() async throws {
        try await withApp { tester, _ in
            let rejected = try await self.send(tester, .GET, "stream/bogus/\(self.trackA)")
            XCTAssertEqual(rejected.status, .unauthorized)

            // an unknown track gives 404 only once the path token has got past auth
            let token = try await self.pairedToken(tester)
            let accepted = try await self.send(tester, .GET, "stream/\(token)/unknown")
            XCTAssertEqual(accepted.status, .notFound)
        }
    }

    func testPairingRequestAndStatusNeedNoToken() async throws {
        try await withApp { tester, _ in
            let requestId = try await self.requestPairing(tester)
            let res = try await self.send(tester, .GET, "pair/status/\(requestId)")
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(PairStatusResponse.self).state, "requested")
        }
    }

    // MARK: - queue

    func testPlayAddsToQueueInOrder() async throws {
        try await withQueue { tester, _, token in
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(try self.queuedHashes(res), [self.trackA, self.trackB, self.trackC])
        }
    }

    func testPlayUnknownTrackIsNotFound() async throws {
        try await withApp { tester, player in
            let token = try await self.pairedToken(tester)
            let res = try await self.send(tester, .GET, "play/unknown", token: token)
            XCTAssertEqual(res.status, .notFound)
            XCTAssertEqual(player.trackQueue, [])
        }
    }

    func testStopAtIndexRemovesThatTrack() async throws {
        try await withQueue { tester, player, token in
            let stop = try await self.send(tester, .GET, "stop/\(self.trackB)/1", token: token)
            XCTAssertEqual(stop.status, .ok)
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(try self.queuedHashes(res), [self.trackA, self.trackC])
            XCTAssertEqual(player.skipCount, 0)
        }
    }

    func testStopAtIndexMinusOneSkips() async throws {
        try await withQueue { tester, player, token in
            let stop = try await self.send(tester, .GET, "stop/\(self.trackA)/-1", token: token)
            XCTAssertEqual(stop.status, .ok)
            XCTAssertEqual(player.skipCount, 1)
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(try self.queuedHashes(res), [self.trackA, self.trackB, self.trackC])
        }
    }

    func testStopWithNonNumericIndexIsBadRequest() async throws {
        try await withQueue { tester, player, token in
            let res = try await self.send(tester, .GET, "stop/\(self.trackA)/x", token: token)
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(player.trackQueue, [self.trackA, self.trackB, self.trackC])
        }
    }

    func testMoveReordersQueue() async throws {
        try await withQueue { tester, _, token in
            let expected = [self.trackB, self.trackC, self.trackA]
            let moved = try await self.send(tester, .GET, "move/\(self.trackA)/0/2", token: token)
            XCTAssertEqual(try self.queuedHashes(moved), expected)
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(try self.queuedHashes(res), expected)
        }
    }

    func testStopClearsQueue() async throws {
        try await withQueue { tester, _, token in
            let stop = try await self.send(tester, .GET, "stop", token: token)
            XCTAssertEqual(stop.status, .ok)
            let res = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(try self.queuedHashes(res), [])
        }
    }

    func testShuffleReachesPlayer() async throws {
        try await withQueue { tester, player, token in
            let res = try await self.send(tester, .GET, "shuffle", token: token)
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(player.shuffleCount, 1)
        }
    }

    // MARK: - history

    // The in-RAM history is shared by all tests, so each one uses its own hash.

    func testPostedPlayIsListedStrictlyAfterSince() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let hash = UUID().uuidString
            let time = 1_700_000_000
            let post = try await self.send(tester, .POST, "history", token: token,
                                           body: HistoryEntry(hash: hash, time: time,
                                                              fullyPlayed: true))
            XCTAssertEqual(post.status, .ok)

            let all = try await self.history(tester, "history", token: token)
            XCTAssertEqual(all.plays[hash], [Double(time)])
            XCTAssertNil(all.skips[hash])

            let before = try await self.history(tester, "history/\(time - 1)", token: token)
            XCTAssertEqual(before.plays[hash], [Double(time)])

            let at = try await self.history(tester, "history/\(time)", token: token)
            XCTAssertNil(at.plays[hash])

            XCTAssertEqual(try jukeboxDatabase.loadHistory().plays[hash], [Double(time)])
        }
    }

    func testPostedSkipIsRecordedAsSkip() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let hash = UUID().uuidString
            let time = 1_700_000_100
            let post = try await self.send(tester, .POST, "history", token: token,
                                           body: HistoryEntry(hash: hash, time: time,
                                                              fullyPlayed: false))
            XCTAssertEqual(post.status, .ok)

            let since = try await self.history(tester, "history/\(time - 1)", token: token)
            XCTAssertEqual(since.skips[hash], [Double(time)])
            XCTAssertNil(since.plays[hash])
            XCTAssertEqual(try jukeboxDatabase.loadHistory().skips[hash], [Double(time)])
        }
    }

    func testHistorySinceNonNumberIsNotFound() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let res = try await self.send(tester, .GET, "history/abc", token: token)
            XCTAssertEqual(res.status, .notFound)
        }
    }

    // MARK: - pairing

    func testPendingListsNewRequest() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let requestId = try await self.requestPairing(tester, name: "Kitchen iPad")
            let res = try await self.send(tester, .GET, "pair/pending", token: token)
            XCTAssertEqual(res.status, .ok)
            let pending = try res.content.decode([PairingService.PendingInfo].self)
            XCTAssertEqual(pending.first { $0.requestId == requestId }?.name, "Kitchen iPad")
        }
    }

    func testPairedDeviceCanApproveAnother() async throws {
        try await withApp { tester, _ in
            let trusted = try await self.pairedToken(tester)
            let requestId = try await self.requestPairing(tester)
            let res = try await self.send(tester, .POST, "pair/approve", token: trusted,
                                          body: PairIdBody(requestId: requestId))
            XCTAssertEqual(res.status, .ok)
            let code = try res.content.decode(PairApproveResponse.self).code

            let response = try await self.claim(tester, requestId, code: code)
            let token = try XCTUnwrap(response.token)
            XCTAssertNotEqual(token, trusted)
            let queue = try await self.send(tester, .GET, "queue", token: token)
            XCTAssertEqual(queue.status, .ok)
        }
    }

    func testDeniedRequestCannotBeClaimed() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let requestId = try await self.requestPairing(tester)
            let deny = try await self.send(tester, .POST, "pair/deny", token: token,
                                           body: PairIdBody(requestId: requestId))
            XCTAssertEqual(deny.status, .ok)
            let claim = try await self.claim(tester, requestId, code: "000000")
            XCTAssertEqual(claim.outcome, "denied")
            XCTAssertNil(claim.token)
        }
    }

    func testClaimBeforeApprovalIsNotApproved() async throws {
        try await withApp { tester, _ in
            let requestId = try await self.requestPairing(tester)
            let claim = try await self.claim(tester, requestId, code: "000000")
            XCTAssertEqual(claim.outcome, "notApproved")
            XCTAssertNil(claim.token)
        }
    }

    func testFiveWrongCodesBurnRequest() async throws {
        try await withApp { tester, _ in
            let requestId = try await self.requestPairing(tester)
            let approved = await pairingService.approve(id: requestId)
            let code = try XCTUnwrap(approved)
            let wrong = code == "000000" ? "000001" : "000000"

            for attempt in 1...5 {
                let claim = try await self.claim(tester, requestId, code: wrong)
                XCTAssertEqual(claim.outcome, "wrongCode", "attempt \(attempt)")
                XCTAssertNil(claim.token)
            }
            let claim = try await self.claim(tester, requestId, code: code)
            XCTAssertEqual(claim.outcome, "unknown")
            XCTAssertNil(claim.token)
        }
    }

    func testPairedTokenSurvivesReload() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let reloaded = PairingService(database: jukeboxDatabase,
                                          tokenHashes: try jukeboxDatabase.loadPairedTokenHashes())
            XCTAssertTrue(reloaded.accepts(token: token))
            XCTAssertFalse(reloaded.accepts(token: "bogus"))
        }
    }

    // MARK: - volume

    func testMasterVolumeRoundTripAndClamp() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            for (requested, stored) in [(-6.0, -6.0), (-50.0, -30.0), (5.0, 0.0)] {
                let post = try await self.send(tester, .POST, "volume/master", token: token,
                                               body: MasterVolume(decibels: requested))
                XCTAssertEqual(post.status, .ok)
                let saved = try await self.decibels(tester, "volume/master", token: token)
                XCTAssertEqual(saved, stored, "requested \(requested)")
            }
        }
    }

    func testTrackVolumeSetListAndClear() async throws {
        try await withApp { tester, _ in
            let token = try await self.pairedToken(tester)
            let adjustment = VolumeAdjustment(scope: "track", sha1: self.trackA,
                                              artist: nil, album: nil, decibels: 6)
            let post = try await self.send(tester, .POST, "volume", token: token,
                                           body: adjustment)
            XCTAssertEqual(post.status, .ok)

            let path = "volume/for/\(self.trackA)"
            let saved = try await self.decibels(tester, path, token: token)
            XCTAssertEqual(saved, 6)

            let list = try await self.send(tester, .GET, "volume", token: token)
            XCTAssertEqual(list.status, .ok)
            let listed = try list.content.decode([VolumeAdjustment].self)
            XCTAssertEqual(listed.first { $0.sha1 == self.trackA }?.decibels, 6)

            let clear = try await self.send(tester, .POST, "volume/clear", token: token,
                                            body: adjustment)
            XCTAssertEqual(clear.status, .ok)
            let cleared = try await self.decibels(tester, path, token: token)
            XCTAssertEqual(cleared, 0)
        }
    }
}
