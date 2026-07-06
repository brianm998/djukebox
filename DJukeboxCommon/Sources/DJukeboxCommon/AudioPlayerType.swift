import Foundation

public protocol AudioPlayerType {
    var isPaused: Bool { get set }
    var trackQueue: [String] { get } // rename to pendingTracks
    var playingTrack: AudioTrackType? { get }

    // The total duration, in seconds, of the sound associated with the audio player.
    var playingTrackDuration: TimeInterval? { get }

    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    var playingTrackPosition: TimeInterval? { get set }
    
    func play(sha1Hash: String)
    func stopPlaying(sha1Hash: String, atIndex index: Int)
    func skip()
    func pause()
    func resume()
    func clearQueue()
    func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool
    func shuffleQueue()

    // Immediately set the playback gain (in dB) of the currently-playing track so
    // a volume adjustment can be auditioned live before it is saved. Best-effort:
    // only the AVAudioEngine-based MacAudioPlayer can change gain mid-track; the
    // subprocess (Linux) and AVQueuePlayer (client-local) players use the no-op
    // default below.
    func setLivePlaybackGain(decibels: Double)

    // The player's current per-channel output loudness (0...1), for the clients'
    // vacuum-tube VU meter. Best-effort: only the AVAudioEngine-based MacAudioPlayer
    // can tap and measure its own output. The Linux subprocess player reports
    // `.unavailable` via the default below (its audio never passes through this
    // process); the client-local players meter their playback tap directly instead
    // of going through this property.
    var outputLevels: AudioLevels { get }
}

public extension AudioPlayerType {
    func setLivePlaybackGain(decibels: Double) { }
    var outputLevels: AudioLevels { .unavailable }
}

