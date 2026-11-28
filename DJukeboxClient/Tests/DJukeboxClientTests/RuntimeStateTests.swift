import Foundation
import Testing
@testable import DJukeboxClient

struct RuntimeStateTests {
    @Test func roundTrips() throws {
        let state = RuntimeState(isPaused: true,
                                 isOffline: true,
                                 playingQueue: .remote,
                                 playingTrack: "a",
                                 playingTrackPosition: 12.5,
                                 pendingTracks: ["b", "c"])

        let decoded = try RuntimeState.decoded(from: state.encoded())

        #expect(decoded.isPaused)
        #expect(decoded.isOffline)
        #expect(decoded.playingQueue == .remote)
        #expect(decoded.playingTrack == "a")
        #expect(decoded.playingTrackPosition == 12.5)
        #expect(decoded.pendingTracks == ["b", "c"])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFinitePositionDecodesAsNil(position: Double) throws {
        let state = RuntimeState(playingQueue: .local,
                                 playingTrack: "a",
                                 playingTrackPosition: position)

        let decoded = try RuntimeState.decoded(from: state.encoded())

        #expect(decoded.playingTrackPosition == nil)
        #expect(decoded.playingTrack == "a")
    }
}
