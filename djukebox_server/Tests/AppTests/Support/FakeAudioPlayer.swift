import Foundation
import DJukeboxCommon

/// Stands in for the real player so route tests never produce audio. It only
/// keeps the queue and records the calls the routes make.
// @unchecked Sendable: tests send one request at a time and read the state only
// after the response has arrived.
final class FakeAudioPlayer: AudioPlayerType, @unchecked Sendable {
    var isPaused = false
    var trackQueue: [String] = []
    var playingTrack: AudioTrackType? { nil }
    var playingTrackDuration: TimeInterval? { nil }
    var playingTrackPosition: TimeInterval?

    private(set) var skipCount = 0
    private(set) var shuffleCount = 0

    func play(sha1Hash: String) { trackQueue.append(sha1Hash) }

    func stopPlaying(sha1Hash: String, atIndex index: Int) {
        guard trackQueue.indices.contains(index), trackQueue[index] == sha1Hash else { return }
        trackQueue.remove(at: index)
    }

    func skip() { skipCount += 1 }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func clearQueue() { trackQueue.removeAll() }

    func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        guard trackQueue.indices.contains(fromIndex),
              trackQueue.indices.contains(toIndex),
              trackQueue[fromIndex] == track.SHA1
        else { return false }
        let hash = trackQueue.remove(at: fromIndex)
        trackQueue.insert(hash, at: toIndex)
        return true
    }

    // order is left alone so tests stay deterministic
    func shuffleQueue() { shuffleCount += 1 }
}
