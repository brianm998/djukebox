import Foundation

public protocol AudioPlayerType {
    var isPlaying: Bool { get }
    //var isPaused: Bool { get }
    var trackQueue: [String] { get }
    var playingTrack: AudioTrack? { get }
    func play(sha1Hash: String)
    func stopPlaying(sha1Hash: String)
    func skip() 
    func pause() 
    func resume()
    func clearQueue()
}

