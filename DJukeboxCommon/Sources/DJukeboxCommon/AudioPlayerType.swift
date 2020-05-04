import Foundation

public protocol AudioTrackType {
    var Artist: String { get }
    var Album: String? { get }
    var Title: String { get }
    var Filename: String { get }
    var SHA1: String { get }
    var Duration: String? { get }
    var AudioBitrate: String? { get }
    var SampleRate: String? { get }
    var TrackNumber: String? { get }
    var Genre: String? { get }
    var OriginalDate: String? { get }
}

public protocol AudioPlayerType {
    var isPlaying: Bool { get }
    //var isPaused: Bool { get }
    var trackQueue: [String] { get }
    var playingTrack: AudioTrackType? { get }

    // The total duration, in seconds, of the sound associated with the audio player.
    var playingTrackDuration: TimeInterval? { get }

    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    var playingTrackPosition: TimeInterval? { get }
    
    func play(sha1Hash: String)
    func stopPlaying(sha1Hash: String, atIndex index: Int)
    func skip() 
    func pause() 
    func resume()
    func clearQueue()
    func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool
}

