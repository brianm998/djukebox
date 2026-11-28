import Foundation
import Testing
@testable import DJukeboxClient

@MainActor
struct TrackFetcherTests {
    @Test func updateTotalsRemainingAndPendingTime() {
        let fetcher = makeFetcher()
        let tracks = [makeTrack("a", duration: "0:05:00"),
                      makeTrack("b", duration: "0:01:00"),
                      makeTrack("c", duration: "0:02:00 (approx)")]
        let before = Date()

        fetcher.update(playingQueue: PlayingQueue(isPaused: false,
                                                  tracks: tracks,
                                                  playingTrackDuration: 300,
                                                  playingTrackPosition: 100))

        #expect(fetcher.currentTrack?.SHA1 == "a")
        #expect(fetcher.pendingTracks.map { $0.SHA1 } == ["b", "c"])
        // 200s left of the first track, plus the full length of the other two
        #expect(fetcher.totalDuration == 380)
        #expect(fetcher.completionTime >= before.addingTimeInterval(380))
        #expect(fetcher.completionTime <= Date(timeIntervalSinceNow: 380))
        #expect(fetcher.progressBarLevel?.level == 100)
        #expect(fetcher.progressBarLevel?.max == 300)
    }

    @Test func updateWithEmptyQueueClearsTotals() {
        let fetcher = makeFetcher()
        fetcher.update(playingQueue: PlayingQueue(isPaused: false,
                                                  tracks: [makeTrack("a"), makeTrack("b")],
                                                  playingTrackDuration: 60,
                                                  playingTrackPosition: 0))

        fetcher.update(playingQueue: PlayingQueue(isPaused: false,
                                                  tracks: [],
                                                  playingTrackDuration: nil,
                                                  playingTrackPosition: nil))

        #expect(fetcher.currentTrack == nil)
        #expect(fetcher.pendingTracks.isEmpty)
        #expect(fetcher.totalDuration == 0)
        #expect(fetcher.progressBarLevel == nil)
    }

    // The wait is on an unstructured task: a continuation that is never resumed
    // can't be cancelled, so awaiting it directly could outlast the time limit.
    @Test(.timeLimit(.minutes(1)))
    func cachingWithoutALocalStoreCompletes() async throws {
        let fetcher = makeFetcher()
        var finished = false
        Task {
            await fetcher.cacheSequentially(tracks: [makeTrack("a"), makeTrack("b")])
            finished = true
        }

        let deadline = Date(timeIntervalSinceNow: 10)
        while !finished && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(finished)
    }
}
