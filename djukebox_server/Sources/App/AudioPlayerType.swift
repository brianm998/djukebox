import Foundation

public protocol AudioPlayerType {
    var isPlaying: Bool { get }
    //var isPaused: Bool { get }
    var trackQueue: [String] { get }
    var playingTrack: AudioTrack? { get }

    // The total duration, in seconds, of the sound associated with the audio player.
    var playingTrackDuration: TimeInterval? { get }

    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    var playingTrackPosition: TimeInterval? { get }
    
    func play(sha1Hash: String)
    func stopPlaying(sha1Hash: String)
    func skip() 
    func pause() 
    func resume()
    func clearQueue()
}

