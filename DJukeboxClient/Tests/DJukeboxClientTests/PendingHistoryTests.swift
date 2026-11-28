import Foundation
import Testing
import DJukeboxCommon
@testable import DJukeboxClient

private struct PostFailed: Error {}

// @unchecked Sendable: all mutable state is guarded by `lock`.
private final class StubServer: ServerType, @unchecked Sendable {
    private let lock = NSLock()
    private var _hasServer = true
    private var _posted: [ServerHistoryEntry] = []
    private var _attempts = 0
    private var _failingHashes: Set<String> = []

    var hasServer: Bool {
        get { lock.withLock { _hasServer } }
        set { lock.withLock { _hasServer = newValue } }
    }
    var failingHashes: Set<String> {
        get { lock.withLock { _failingHashes } }
        set { lock.withLock { _failingHashes = newValue } }
    }
    var posted: [ServerHistoryEntry] { lock.withLock { _posted } }
    var attempts: Int { lock.withLock { _attempts } }

    func post(history: ServerHistoryEntry) async throws {
        try lock.withLock {
            _attempts += 1
            if _failingHashes.contains(history.hash) { throw PostFailed() }
            _posted.append(history)
        }
    }

    func listTracks() async throws -> [AudioTrack] { [] }
    func listHistory() async throws -> PlayingHistory { PlayingHistory() }
    func listHistory(since: Int) async throws -> PlayingHistory { PlayingHistory() }
    func setVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws {}
    func clearVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws {}
    func listVolumeAdjustments() async throws -> [VolumeAdjustment] { [] }
    func savedGain(forHash hash: String) async throws -> Double? { nil }
    func masterGain() async throws -> Double? { nil }
    func setMasterGain(_ decibels: Double) async throws {}
    var authHeaderValue: String { "token" }
    var url: String { "" }
}

private final class TempStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pending-history-\(UUID().uuidString)")
    var path: String { directory.appendingPathComponent("db.sqlite3").path }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func open() throws -> LocalDatabase { try #require(LocalDatabase(path: path)) }
}

private func entry(_ hash: String, _ time: Int, played: Bool = true) -> ServerHistoryEntry {
    ServerHistoryEntry(hash: hash, time: time, fullyPlayed: played)
}

// empties the store, returning what was in it, in upload order
private func takeAll(_ store: LocalDatabase) -> [ServerHistoryEntry] {
    var entries: [ServerHistoryEntry] = []
    while let row = store.oldestPendingHistory() {
        entries.append(row.entry)
        guard store.deletePendingHistory(id: row.id) else { break }
    }
    return entries
}

@Test func offlineRecordIsStoredNotPosted() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    let queue = PendingHistoryQueue(server: server, store: store)

    await queue.record(entry("a", 10), online: false)
    await queue.record(entry("b", 20, played: false), online: false)

    #expect(server.attempts == 0)
    // survives reopening the database, as across an app restart
    #expect(takeAll(try temp.open()) == [entry("a", 10), entry("b", 20, played: false)])
}

@Test func noServerKeepsEntries() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    server.hasServer = false
    let queue = PendingHistoryQueue(server: server, store: store)

    await queue.record(entry("a", 10), online: false)
    await queue.drain()

    #expect(server.attempts == 0)
    #expect(takeAll(store) == [entry("a", 10)])
}

@Test func drainPostsInTimeOrderAndRemoves() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    let queue = PendingHistoryQueue(server: server, store: store)
    for item in [entry("c", 30), entry("a", 10), entry("b", 20, played: false)] {
        await queue.record(item, online: false)
    }

    await queue.drain()

    #expect(server.posted == [entry("a", 10), entry("b", 20, played: false), entry("c", 30)])
    #expect(store.oldestPendingHistory() == nil)
}

@Test func failedPostKeepsThatEntryAndLaterOnes() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    let queue = PendingHistoryQueue(server: server, store: store)
    for item in [entry("a", 10), entry("b", 20), entry("c", 30)] {
        await queue.record(item, online: false)
    }
    server.failingHashes = ["b"]

    await queue.drain()

    #expect(server.posted == [entry("a", 10)])
    #expect(server.attempts == 2)   // "c" is not tried past the failure
    #expect(!store.hasPendingHistory(sha1: "a", fullyPlayed: true))
    #expect(store.hasPendingHistory(sha1: "b", fullyPlayed: true))
    #expect(store.hasPendingHistory(sha1: "c", fullyPlayed: true))

    server.failingHashes = []
    await queue.drain()

    #expect(server.posted == [entry("a", 10), entry("b", 20), entry("c", 30)])
    #expect(store.oldestPendingHistory() == nil)
}

@Test func failedOnlinePostIsKept() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    server.failingHashes = ["a"]
    let queue = PendingHistoryQueue(server: server, store: store)

    await queue.record(entry("a", 10), online: true)

    #expect(server.attempts == 1)
    #expect(takeAll(store) == [entry("a", 10)])
}

@Test func onlineRecordPostsOnceAndLeavesNothing() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    let queue = PendingHistoryQueue(server: server, store: store)

    await queue.record(entry("a", 10, played: false), online: true)

    #expect(server.posted == [entry("a", 10, played: false)])
    #expect(server.attempts == 1)
    #expect(store.oldestPendingHistory() == nil)
}

@Test func onlineRecordWithoutStorePostsDirectly() async {
    let server = StubServer()
    let queue = PendingHistoryQueue(server: server, store: nil)

    await queue.record(entry("a", 10), online: true)

    #expect(server.posted == [entry("a", 10)])
}

@Test func clearingTracksKeepsPendingHistory() throws {
    let temp = try TempStore()
    let store = try temp.open()
    store.appendPendingHistory(entry("a", 10))

    store.clear()

    #expect(takeAll(store) == [entry("a", 10)])
}

@MainActor
@Test func historyFetcherSeesPendingAndUploadedEntries() async throws {
    let temp = try TempStore()
    let store = try temp.open()
    let server = StubServer()
    server.hasServer = false   // no initial history fetch
    let history = HistoryFetcher(withServer: server,
                                 trackFetcher: TrackFetcher(withServer: server),
                                 pendingHistory: store)
    let queue = PendingHistoryQueue(server: server, store: store,
                                    onPosted: { await history.noteUploaded($0) })

    await queue.record(entry("played", 10), online: false)
    await queue.record(entry("skipped", 20, played: false), online: false)

    #expect(history.hasPlay(for: "played"))
    #expect(!history.hasSkip(for: "played"))
    #expect(history.hasSkip(for: "skipped"))
    #expect(!history.hasPlay(for: "skipped"))
    #expect(!history.hasPlay(for: "other"))

    server.hasServer = true
    await queue.drain()

    // no longer pending, but still known
    #expect(store.oldestPendingHistory() == nil)
    #expect(history.hasPlay(for: "played"))
    #expect(history.hasSkip(for: "skipped"))
}
