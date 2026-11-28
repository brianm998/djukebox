import Testing
@testable import DJukeboxClient

@MainActor
struct TrackFetcherRestoreTests {
    // persistRuntimeState() isn't called here: it writes into the real library
    // directory. It saves only when isAwaitingSavedState is false.
    @Test func savedLocalQueueIsPendingUntilTheCatalogLoads() {
        let fetcher = makeFetcher()
        #expect(!fetcher.isAwaitingSavedState)

        // no local player is registered, so initialize() logs that it can't watch
        fetcher.initialize(with: RuntimeState(playingQueue: .local, playingTrack: "a"))
        #expect(fetcher.isAwaitingSavedState)

        // going local loads the (empty) local catalog synchronously
        fetcher.useLocalContentOnly = true
        #expect(!fetcher.isAwaitingSavedState)
    }
}
