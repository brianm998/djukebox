import Foundation
import Testing
@testable import DJukeboxClient

@MainActor
struct AsyncAudioPlayerTests {
    // AsyncAudioPlayer and HistoryFetcher hold the fetcher weakly, so each test
    // has to keep it alive until it is done
    private func makePlayer(tracks: [AudioTrack]) -> (AsyncAudioPlayer, FakeAudioPlayer, TrackFetcher) {
        let fetcher = makeFetcher(tracks: tracks)
        let fake = FakeAudioPlayer()
        let history = HistoryFetcher(withServer: OfflineServer(), trackFetcher: fetcher)
        return (AsyncAudioPlayer(player: fake, fetcher: fetcher, history: history), fake, fetcher)
    }

    @Test func playTrackQueuesItAndResumes() async throws {
        let (player, fake, fetcher) = makePlayer(tracks: [makeTrack("a")])
        fake.isPaused = true

        let track = try await player.playTrack(withHash: "a")

        #expect(track.SHA1 == "a")
        #expect(fake.trackQueue == ["a"])
        #expect(!fake.isPaused)
        withExtendedLifetime(fetcher) {}
    }

    @Test func playTrackRejectsUnknownHash() async {
        let (player, fake, fetcher) = makePlayer(tracks: [makeTrack("a")])
        fake.isPaused = true

        await #expect(throws: AudioPlayerError.trackNotFound) {
            _ = try await player.playTrack(withHash: "nope")
        }
        #expect(fake.trackQueue.isEmpty)
        #expect(fake.isPaused)
        withExtendedLifetime(fetcher) {}
    }

    @Test func playingQueueIsPlayingTrackThenKnownQueuedTracks() async throws {
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        let (player, fake, fetcher) = makePlayer(tracks: tracks)
        fake.playingTrack = tracks[2]
        fake.playingTrackDuration = 60
        fake.playingTrackPosition = 10
        fake.trackQueue = ["b", "unknown", "a"]
        fake.isPaused = true

        let queue = try await player.listPlayingQueue()

        #expect(queue.tracks.map { $0.SHA1 } == ["c", "b", "a"])
        #expect(queue.isPaused)
        #expect(queue.playingTrackDuration == 60)
        #expect(queue.playingTrackPosition == 10)
        withExtendedLifetime(fetcher) {}
    }

    @Test func playUntilFillsTheRemainingTime() async throws {
        let playing = makeTrack("playing", duration: "0:01:40")
        let queued = makeTrack("queued")
        let fillers = ["x", "y", "z"].map { makeTrack($0) }
        let unusable = [makeTrack("long", duration: "1:00:00"),
                        makeTrack("empty", duration: "0:00:00"),
                        makeTrack("unknown", duration: nil)]
        let (player, fake, fetcher) = makePlayer(tracks: [playing, queued] + fillers + unusable)
        fake.playingTrack = playing
        fake.playingTrackDuration = 100
        fake.playingTrackPosition = 40
        fake.trackQueue = ["queued"]

        // 60s left of the playing track + 60s queued + room for two more
        // (150s, well clear of both the two and three track boundaries)
        let queue = try await player.playUntil(date: Date(timeIntervalSinceNow: 270))

        let added = fake.trackQueue.dropFirst()
        #expect(added.count == 2)
        #expect(Set(added).count == 2)
        #expect(Set(added).isSubset(of: ["x", "y", "z"]))
        #expect(queue.tracks.map { $0.SHA1 } == ["playing", "queued"] + added)
        withExtendedLifetime(fetcher) {}
    }

    @Test func playUntilThePastAddsNothing() async throws {
        let (player, fake, fetcher) = makePlayer(tracks: [makeTrack("a")])

        let queue = try await player.playUntil(date: Date(timeIntervalSinceNow: -60))

        #expect(queue.tracks.isEmpty)
        #expect(fake.trackQueue.isEmpty)
        withExtendedLifetime(fetcher) {}
    }

    @Test func pendingIndexesAreQueueIndexesWhileATrackIsPlaying() async throws {
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        let (player, fake, fetcher) = makePlayer(tracks: tracks)
        fake.playingTrack = tracks[0]
        fake.trackQueue = ["b", "c"]

        _ = try await player.movePlayingTrack(withHash: "c", fromIndex: 1, toIndex: 0)
        _ = try await player.stopPlayingTrack(withHash: "c", atIndex: 1)
        _ = try await player.stopPlayingTrack(withHash: "a", atIndex: -1)

        #expect(fake.moves == [[1, 0]])
        #expect(fake.stoppedIndexes == [1, -1])
        withExtendedLifetime(fetcher) {}
    }

    @Test func pendingIndexesSkipTheQueueHeadWhenNothingIsPlaying() async throws {
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        let (player, fake, fetcher) = makePlayer(tracks: tracks)
        fake.trackQueue = ["a", "b", "c"]

        _ = try await player.movePlayingTrack(withHash: "c", fromIndex: 1, toIndex: 0)
        _ = try await player.stopPlayingTrack(withHash: "c", atIndex: 1)
        _ = try await player.stopPlayingTrack(withHash: "a", atIndex: -1)

        #expect(fake.moves == [[2, 1]])
        #expect(fake.stoppedIndexes == [2, -1])
        withExtendedLifetime(fetcher) {}
    }

    @Test func negativePendingIndexIsNotMoved() async {
        let (player, fake, fetcher) = makePlayer(tracks: [makeTrack("a"), makeTrack("b")])
        fake.trackQueue = ["a", "b"]

        await #expect(throws: AudioPlayerError.moveFailed) {
            _ = try await player.movePlayingTrack(withHash: "a", fromIndex: -1, toIndex: 0)
        }
        #expect(fake.moves.isEmpty)
        withExtendedLifetime(fetcher) {}
    }
}
