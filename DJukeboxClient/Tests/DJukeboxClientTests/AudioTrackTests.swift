import Testing
@testable import DJukeboxClient

struct AudioTrackTests {
    @Test(arguments: ["0:07:11", "0:07:11 (approx)"])
    func parsesDuration(_ duration: String) {
        let track = makeTrack("a", duration: duration)
        #expect(track.timeInterval == 431)
        #expect(track.timeIntervalString == "7:11")
    }

    @Test func formatsShortDurationInSeconds() {
        #expect(makeTrack("a", duration: "0:00:42").timeIntervalString == "42s")
    }

    @Test func missingDurationHasNoInterval() {
        let track = makeTrack("a", duration: nil)
        #expect(track.timeInterval == nil)
        #expect(track.timeIntervalString == "")
    }

    @Test(arguments: ["", " ", "nan:nan:nan", "1:2", "inf:0:0", "0:-1:00",
                      "1e308:0:0", "0:07:xx", "(approx)"])
    func unparseableDurationIsUnknown(_ duration: String) {
        let track = makeTrack("a", duration: duration)
        #expect(track.timeInterval == nil)
        #expect(track.timeIntervalString == "")
    }

    @Test func hugeDurationIsNotFormatted() {
        #expect(makeTrack("a", duration: "1e300:0:0").timeIntervalString == "")
    }
}
