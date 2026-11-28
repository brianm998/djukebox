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

    @Test(arguments: [(300, Double.nan), (300, .infinity), (300, -.infinity),
                      (Double.nan, 100), (.infinity, 100), (0, 0)])
    func updateWithUnusableTimesKeepsTotalsFinite(duration: Double, position: Double) {
        let fetcher = makeFetcher()
        fetcher.update(playingQueue: PlayingQueue(isPaused: false,
                                                  tracks: [makeTrack("a"), makeTrack("b")],
                                                  playingTrackDuration: duration,
                                                  playingTrackPosition: position))

        // only the pending track can be counted
        #expect(fetcher.totalDuration == 60)
        #expect(fetcher.progressBarLevel == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func updateProgressIgnoresNonFinitePosition(position: Double) {
        let fetcher = makeFetcher()
        fetcher.updateProgress(position: position, duration: 300)

        #expect(fetcher.progressBarLevel == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude])
    func formatOfUnusableDurationIsEmpty(duration: Double) {
        #expect(format(duration: duration) == "")
    }

    @Test func formatPicksTheLargestUnit() {
        #expect(format(duration: 59.9) == "59 seconds")
        #expect(format(duration: 61) == "1 minutes")
        #expect(format(duration: 7300) == "2 hours")
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
}
