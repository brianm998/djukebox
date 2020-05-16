import Foundation
import DJukeboxCommon

public class LinuxAudioPlayer: AudioPlayerType {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPaused = true

    public var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType
    let historyWriter: HistoryWriter // not written to in linux yet
    
    public var playingTrack: AudioTrackType? 

    // XXX implement this for linux
    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackDuration: TimeInterval?

    // XXX implement this for linux
    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval?

    fileprivate var process: Process?
    
    init(trackFinder: TrackFinderType, historyWriter: HistoryWriter) {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
    }

    public func clearQueue() {
        trackQueue = []
    }

    public func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        return false
    }
    
    fileprivate func playingDone() {
        self.playingTrack = nil
        self.isPaused = true
        Log.d("calling serviceQueue from playingDone()")
        self.serviceQueue()
    }
    
    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        Log.d("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");
        for (index, hash) in trackQueue.enumerated() {
            Log.d("index \(index) hash \(sha1Hash)")
            if hash == sha1Hash {
                Log.d("index \(index) needs to be removed")
                if index == 0 {
                    trackQueue = Array(trackQueue[1..<trackQueue.count])
                } else if index == trackQueue.count - 1 {
                    trackQueue = Array(trackQueue[0..<index])
                } else if index < trackQueue.count {
                    trackQueue = Array(trackQueue[0..<index]) + Array(trackQueue[index+1..<trackQueue.count])
                } else {
                    Log.d("DOH")
                }
            }
        }
    }
    
    public func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        trackQueue.append(sha1Hash)
        Log.d("calling serviceQueue from play")
        serviceQueue()
    }

    // skips the currently playing song, removing it from the playlist
    public func skip() {
        if let process = self.process,
           process.isRunning
        {
            process.terminate()
            self.process = nil
        }
    }

    public func pause() {
        Log.d("calling pause")
        if let process = self.process,
           process.isRunning
        {
            Log.d("calling suspend on pid \(process.processIdentifier)")
            if process.suspend() {
                Log.d("suspended properly?")
            } else {
                Log.d("not suspended properly?")
            }
        } else {
            Log.d("no process")
        }
    }
    
    public func resume() {
        if let process = self.process,
           process.isRunning
        {
            _ = process.resume()
        }
    }

    fileprivate func serviceQueue() {
        guard trackQueue.count > 0 else { return }
        guard isPaused else { return }
        let nextTrackHash = trackQueue.removeFirst()
        self.playingTrack = trackFinder.audioTrack(forHash: nextTrackHash)
        
        isPaused = false
        dispatchQueue.async {
            do {
                if let (audioTrack, url) = self.trackFinder.track(forHash: nextTrackHash) {
                    Log.d("playing \(audioTrack.Title)")
                    try self.play(filename: url.path)
                } else {
                    Log.d("no track exists for hash \(nextTrackHash)")
                    // XXX throw missing value for hash
                }
            } catch {
                Log.d("error \(error)")
            }
            Log.d("linux calling playingDone")
            self.playingDone()
        }
    }

    fileprivate func play(filename: String) throws {
        // linux: aplay, osx: afplay
        var player: String = "afplay" 
        player = "aplay"
        let newProcess = Process()
        self.process = newProcess
        try shellOut(to: player,
                     arguments: ["\"\(filename)\""],
                     process: newProcess)
    }
}
