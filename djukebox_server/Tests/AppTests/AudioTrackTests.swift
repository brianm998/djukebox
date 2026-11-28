@testable import App
import XCTest

// Pure value tests: no server state, so they live outside AppTests.
final class AudioTrackTests: XCTestCase {
    func testParsesDuration() {
        for duration in ["0:07:11", "0:07:11 (approx)"] {
            XCTAssertEqual(track(duration: duration).timeInterval, 431, duration)
        }
    }

    func testUnparseableDurationIsUnknown() {
        for duration in [nil, "", " ", "nan:nan:nan", "1:2", "inf:0:0", "0:-1:00",
                         "1e308:0:0", "0:07:xx", "(approx)"] {
            XCTAssertNil(track(duration: duration).timeInterval, duration ?? "nil")
        }
    }

    private func track(duration: String?) -> App.AudioTrack {
        App.AudioTrack(Credit: "c", Artist: "a", Album: nil, Conductor: nil,
                       Title: "t", Filename: "f", SHA1: "s", Duration: duration,
                       AudioBitrate: nil, SampleRate: nil, TrackNumber: nil,
                       Genre: nil, Year: nil, OriginalDate: nil)
    }
}
