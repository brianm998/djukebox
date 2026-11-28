import Foundation
import Testing
import DJukeboxCommon
@testable import DJukeboxClient

private struct FakeHistoryWriter: HistoryWriterType {
    func writePlay(of sha1: String, at date: Date) throws {}
    func writeSkip(of sha1: String, at date: Date) throws {}
}

// Queue edits on a real doghouse player. Setting trackQueue directly leaves its
// AVQueuePlayer empty, as after a failed item.
@MainActor
struct AVDoghouseAudioPlayerQueueTests {
    private func makeDoghouse(queue: [String]) -> AVDoghouseAudioPlayer {
        let catalog = TrackCatalog(serverURL: "", authHeaderValue: "local")
        let player = AVDoghouseAudioPlayer(trackFinder: catalog,
                                           historyWriter: FakeHistoryWriter())
        player.trackQueue = queue
        return player
    }

    @Test(arguments: [(-1, 0), (3, 0), (0, -1), (0, 3)])
    func moveRejectsOutOfRangeIndexes(from: Int, to: Int) {
        let player = makeDoghouse(queue: ["a", "b", "c"])

        #expect(!player.move(track: makeTrack("a"), fromIndex: from, toIndex: to))
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test func moveOnAnEmptyQueueFails() {
        let player = makeDoghouse(queue: [])

        #expect(!player.move(track: makeTrack("a"), fromIndex: 0, toIndex: 0))
        #expect(player.trackQueue.isEmpty)
    }

    @Test func moveRejectsATrackThatIsNotQueued() {
        let player = makeDoghouse(queue: ["a", "b", "c"])

        #expect(!player.move(track: makeTrack("gone"), fromIndex: 0, toIndex: 2))
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test func moveReorders() {
        let player = makeDoghouse(queue: ["a", "b", "c"])

        #expect(player.move(track: makeTrack("a"), fromIndex: 0, toIndex: 2))
        #expect(player.trackQueue == ["b", "c", "a"])
        #expect(player.move(track: makeTrack("a"), fromIndex: 2, toIndex: 0))
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test func moveFindsATrackWhoseIndexIsStale() {
        let player = makeDoghouse(queue: ["a", "b", "c"])

        #expect(player.move(track: makeTrack("b"), fromIndex: 2, toIndex: 0))
        #expect(player.trackQueue == ["b", "a", "c"])
    }

    @Test func stopRemovesTheEntryAtTheIndex() {
        let player = makeDoghouse(queue: ["a", "b", "a"])

        player.stopPlaying(sha1Hash: "a", atIndex: 2)

        #expect(player.trackQueue == ["a", "b"])
    }

    @Test(arguments: [0, 7])
    func stopFindsATrackWhoseIndexIsStale(index: Int) {
        let player = makeDoghouse(queue: ["a", "b", "c"])

        player.stopPlaying(sha1Hash: "b", atIndex: index)

        #expect(player.trackQueue == ["a", "c"])
    }

    @Test(arguments: [("gone", 0), ("a", -1), ("a", -2)])
    func stopLeavesTheQueueAlone(hash: String, index: Int) {
        let player = makeDoghouse(queue: ["a", "b"])

        player.stopPlaying(sha1Hash: hash, atIndex: index)

        #expect(player.trackQueue == ["a", "b"])
    }

    @Test func moveAndStopWithAnEmptyAVQueuePlayerActOnTheShownTrack() async throws {
        let fetcher = makeFetcher(tracks: ["a", "b", "c", "d"].map { makeTrack($0) })
        let history = HistoryFetcher(withServer: OfflineServer(), trackFetcher: fetcher)
        let doghouse = makeDoghouse(queue: ["a", "b", "c", "d"])
        let player = AsyncAudioPlayer(player: doghouse, fetcher: fetcher, history: history)

        // "a" is shown as current, so pending is b, c, d
        let queue = try await player.movePlayingTrack(withHash: "d", fromIndex: 2, toIndex: 0)
        #expect(queue.tracks.map { $0.SHA1 } == ["a", "d", "b", "c"])

        _ = try await player.stopPlayingTrack(withHash: "b", atIndex: 1)
        #expect(doghouse.trackQueue == ["a", "d", "c"])
    }
}
