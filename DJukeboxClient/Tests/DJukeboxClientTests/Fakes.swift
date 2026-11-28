import Foundation
import DJukeboxCommon
@testable import DJukeboxClient

func makeTrack(_ hash: String, duration: String? = "0:01:00") -> AudioTrack {
    AudioTrack(Credit: "Credit", Artist: "Artist", Album: "Album", Conductor: nil,
               Title: hash, Filename: "\(hash).mp3", SHA1: hash, Duration: duration,
               AudioBitrate: nil, SampleRate: nil, TrackNumber: nil,
               Genre: nil, Year: nil, OriginalDate: nil)
}

// A client with no server, like the offline / local-only one.
struct OfflineServer: ServerType {
    var authHeaderValue: String { "local" }
    var url: String { "" }
    var hasServer: Bool { false }

    func listTracks() async throws -> [AudioTrack] { throw ServerConnectionError.notConnected }
    func listHistory() async throws -> PlayingHistory { throw ServerConnectionError.notConnected }
    func listHistory(since: Int) async throws -> PlayingHistory { throw ServerConnectionError.notConnected }
    func post(history: ServerHistoryEntry) async throws { throw ServerConnectionError.notConnected }
    func setVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws { throw ServerConnectionError.notConnected }
    func clearVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws { throw ServerConnectionError.notConnected }
    func listVolumeAdjustments() async throws -> [VolumeAdjustment] { throw ServerConnectionError.notConnected }
    func savedGain(forHash hash: String) async throws -> Double? { throw ServerConnectionError.notConnected }
    func masterGain() async throws -> Double? { throw ServerConnectionError.notConnected }
    func setMasterGain(_ decibels: Double) async throws { throw ServerConnectionError.notConnected }
}

// Records what it is asked to do; plays no audio. `play` only appends to the
// queue, so a test decides what is "playing" by setting playingTrack.
final class FakeAudioPlayer: AudioPlayerType {
    var isPaused = false
    var trackQueue: [String] = []
    var playingTrack: AudioTrackType?
    var playingTrackDuration: TimeInterval?
    var playingTrackPosition: TimeInterval?

    func play(sha1Hash: String) { trackQueue.append(sha1Hash) }
    func stopPlaying(sha1Hash: String, atIndex index: Int) {}
    func skip() {}
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func clearQueue() { trackQueue = [] }
    func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool { false }
    func shuffleQueue() {}
}

@MainActor
func makeFetcher(tracks: [AudioTrack] = []) -> TrackFetcher {
    let fetcher = TrackFetcher(withServer: OfflineServer())
    fetcher.allTracks = tracks
    fetcher.trackMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.SHA1, $0) })
    return fetcher
}
