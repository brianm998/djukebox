import Foundation
import Testing
@testable import DJukeboxCommon

private struct FakeTrack: AudioTrackType {
    let SHA1: String
    var Credit: String { "credit" }
    var Album: String? { nil }
    var Title: String { SHA1 }
    var Filename: String { "\(SHA1).mp3" }
    var Duration: String? { nil }
    var timeInterval: Double? { nil }
    var AudioBitrate: String? { nil }
    var SampleRate: String? { nil }
    var TrackNumber: String? { nil }
    var Genre: String? { nil }
    var OriginalDate: String? { nil }
}

private struct FakeTrackFinder: TrackFinderType {
    func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? { nil }
    func audioTrack(forHash sha1Hash: String) -> AudioTrackType? { nil }
}

private struct FakeHistoryWriter: HistoryWriterType {
    func writePlay(of sha1: String, at date: Date) throws {}
    func writeSkip(of sha1: String, at date: Date) throws {}
}

@Suite struct MacAudioPlayerMoveTests {
    // A player whose pending queue is `queue`. Marking it as already playing
    // keeps serviceQueue() from draining what play() appends.
    private func makePlayer(queue: [String]) -> MacAudioPlayer {
        let player = MacAudioPlayer(trackFinder: FakeTrackFinder(),
                                    historyWriter: FakeHistoryWriter(),
                                    volumeSource: nil)
        player.isPlaying = true
        for hash in queue {
            player.play(sha1Hash: hash)
        }
        player.dispatchQueue.sync {}
        return player
    }

    @Test func movesFirstEntryToLast() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "a"), fromIndex: 0, toIndex: 2)

        #expect(result)
        #expect(player.trackQueue == ["b", "c", "a"])
    }

    @Test func movesLastEntryToFront() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "c"), fromIndex: 2, toIndex: 0)

        #expect(result)
        #expect(player.trackQueue == ["c", "a", "b"])
    }

    @Test func movingToTheSameIndexChangesNothing() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "b"), fromIndex: 1, toIndex: 1)

        #expect(result)
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test func rejectsTrackThatIsNotAtFromIndex() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "b"), fromIndex: 0, toIndex: 2)

        withKnownIssue("move ignores the track check, see #1311") {
            #expect(!result)
            #expect(player.trackQueue == ["a", "b", "c"])
        }
    }

    @Test(.disabled("traps: MacAudioPlayer.move guard is dead code, #1311"))
    func rejectsNegativeFromIndex() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "a"), fromIndex: -1, toIndex: 0)

        #expect(!result)
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test(.disabled("traps: MacAudioPlayer.move guard is dead code, #1311"))
    func rejectsFromIndexPastTheEnd() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "a"), fromIndex: 3, toIndex: 0)

        #expect(!result)
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test(.disabled("traps: MacAudioPlayer.move guard is dead code, #1311"))
    func rejectsNegativeToIndex() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "a"), fromIndex: 0, toIndex: -1)

        #expect(!result)
        #expect(player.trackQueue == ["a", "b", "c"])
    }

    @Test(.disabled("traps: MacAudioPlayer.move guard is dead code, #1311"))
    func rejectsToIndexPastTheEnd() {
        let player = makePlayer(queue: ["a", "b", "c"])

        let result = player.move(track: FakeTrack(SHA1: "a"), fromIndex: 0, toIndex: 3)

        #expect(!result)
        #expect(player.trackQueue == ["a", "b", "c"])
    }
}
