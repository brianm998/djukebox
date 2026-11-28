import Foundation
import Testing
import DJukeboxCommon
@testable import DJukeboxClient

// A local cache holding a fixed set of tracks; touches no disk.
private final class StubLocalTracks: LocalTrackType {
    let downloadedTracks: [AudioTrack]
    let downloadedTrackMap: [String: AudioTrack]

    init(_ tracks: [AudioTrack]) {
        downloadedTracks = tracks
        downloadedTrackMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.SHA1, $0) })
    }

    func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        downloadedTrackMap[sha1Hash].map { ($0, URL(fileURLWithPath: "/nonexistent/\(sha1Hash).mp3")) }
    }
    func audioTrack(forHash sha1Hash: String) -> AudioTrackType? { downloadedTrackMap[sha1Hash] }
    func keepLocal(sha1Hash: String, closure: @escaping @Sendable (Bool) -> Void) { closure(false) }
    func clearLocalStore() {}
}

@MainActor
struct RestoreStateTests {
    private let cached = [makeTrack("a"), makeTrack("b"), makeTrack("c")]

    private func makeOfflineFetcher() -> (TrackFetcher, FakeAudioPlayer) {
        let fetcher = makeFetcher()
        let fake = FakeAudioPlayer()
        let history = HistoryFetcher(withServer: OfflineServer(), trackFetcher: fetcher)
        fetcher.add(queueType: .local,
                    withPlayer: AsyncAudioPlayer(player: fake, fetcher: fetcher, history: history))
        fetcher.localTracks = StubLocalTracks(cached)
        return (fetcher, fake)
    }

    @Test func offlineRelaunchRestoresTheLocalQueue() {
        let (fetcher, fake) = makeOfflineFetcher()

        fetcher.initialize(with: RuntimeState(isPaused: true,
                                              isOffline: true,
                                              playingQueue: .local,
                                              playingTrack: "a",
                                              playingTrackPosition: 12,
                                              pendingTracks: ["b", "missing-hash"]))

        #expect(fake.trackQueue == ["a", "b"])
        #expect(fake.isPaused)
        #expect(fake.playingTrackPosition == 12)
        #expect(fetcher.queueType == .local)
        #expect(fetcher.useLocalContentOnly)
    }

    @Test func missingPlayingTrackDropsItsSavedPosition() {
        let (fetcher, fake) = makeOfflineFetcher()

        fetcher.initialize(with: RuntimeState(isOffline: true,
                                              playingQueue: .local,
                                              playingTrack: "missing-hash",
                                              playingTrackPosition: 12,
                                              pendingTracks: ["b"]))

        #expect(fake.trackQueue == ["b"])
        #expect(fake.playingTrackPosition == nil)
    }

    @Test func loadedCatalogSkipsMissingPendingTracks() {
        let (fetcher, _) = makeOfflineFetcher()
        fetcher.trackMap = fetcher.localTracks?.downloadedTrackMap ?? [:]

        fetcher.initialize(with: RuntimeState(isOffline: true,
                                              playingQueue: .local,
                                              playingTrack: "a",
                                              pendingTracks: ["missing-hash", "c"]))

        #expect(fetcher.currentTrack?.SHA1 == "a")
        #expect(fetcher.pendingTracks.map { $0.SHA1 } == ["c"])
    }
}
