import Foundation

public protocol AsyncAudioPlayerType {
    var isPaused: Bool { get }

    var playingTrackPosition: TimeInterval { get }
    
    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func playTracks(_ tracks: [AudioTrack], closure: @escaping (Bool, Error?) -> Void)
    func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int/*? = nil*/,
                          closure: @escaping (Bool, Error?) -> Void)
    func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int,
                          closure: @escaping (PlayingQueue?, Error?) -> Void)
    func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void)
    func update(with runtimeState: RuntimeState)
    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func playRandomTrack(forBand band: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func playNewRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func playNewRandomTrack(forBand band: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func clearPlayingQueue(closure: @escaping (Bool, Error?) -> Void)
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void)
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void)
    func shuffleQueue()
    func playUntil(date: Date, closure: @escaping (PlayingQueue?, Error?) -> Void)

    // Immediately set the currently-playing track's playback gain (dB) for live
    // auditioning of a volume adjustment. Routes to the server (remote queue) or
    // the local playback tap (local queue). No-op default for players that can't.
    func setLivePlaybackGain(decibels: Double)
}

public extension AsyncAudioPlayerType {
    func setLivePlaybackGain(decibels: Double) { }
}

