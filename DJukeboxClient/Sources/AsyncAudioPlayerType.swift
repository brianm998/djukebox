import Foundation

// Errors thrown by AsyncAudioPlayerType conformers when a playback command can't
// be carried out locally (no such track, no track available to pick, etc). The
// remote implementation (ServerAudioPlayer) surfaces the server's own errors
// instead of these.
public enum AudioPlayerError: Error {
    case trackNotFound
    case noTrackAvailable
    case moveFailed
}

public protocol AsyncAudioPlayerType {
    var isPaused: Bool { get }

    var playingTrackPosition: TimeInterval { get }

    func playTrack(withHash hash: String) async throws -> AudioTrack
    func playTracks(_ tracks: [AudioTrack]) async throws -> Bool
    func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int/*? = nil*/) async throws -> Bool
    func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int) async throws -> PlayingQueue
    func listPlayingQueue() async throws -> PlayingQueue
    func update(with runtimeState: RuntimeState)
    func playRandomTrack() async throws -> AudioTrack
    func playRandomTrack(forArtist artist: String) async throws -> AudioTrack
    func playNewRandomTrack() async throws -> AudioTrack
    func playNewRandomTrack(forArtist artist: String) async throws -> AudioTrack
    func clearPlayingQueue() async throws -> Bool
    func pausePlaying() async throws -> Bool
    func resumePlaying() async throws -> Bool
    func shuffleQueue()
    func playUntil(date: Date) async throws -> PlayingQueue

    // Immediately set the currently-playing track's playback gain (dB) for live
    // auditioning of a volume adjustment. Routes to the server (remote queue) or
    // the local playback tap (local queue). No-op default for players that can't.
    func setLivePlaybackGain(decibels: Double)
}

public extension AsyncAudioPlayerType {
    func setLivePlaybackGain(decibels: Double) { }
}
