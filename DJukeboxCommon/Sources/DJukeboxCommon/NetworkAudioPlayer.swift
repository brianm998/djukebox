import Foundation
import AVFoundation
import Dispatch

public class NetworkAudioPlayer: NSObject, AudioPlayerType, AVAudioPlayerDelegate {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPlaying = false

    public var trackQueue: [String] = []

    fileprivate var trackQueueSemaphore = DispatchSemaphore(value: 1)
    
    public var playingTrack: AudioTrackType?

    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval? {
        if let player = player {
            let currentTime = player.currentTime()
            // convert to seconds
            return Double(currentTime.value)/Double(currentTime.timescale)
        }
        return nil
    }

    public var playingTrackDuration: TimeInterval? {
        // The playback point, in seconds, within the timeline of the sound associated with the audio player.
        if let playingTrack = playingTrack { return playingTrack.timeInterval }
        return nil
    }

    public var isPaused = false

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType
    
    var player: AVPlayer? 
    
    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType) {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerDidFinishPlaying),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func clearQueue() {
        self.trackQueueSemaphore.wait()
        trackQueue = []
        self.trackQueueSemaphore.signal()
    }

    public func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        self.trackQueueSemaphore.wait()
        if fromIndex < 0,
           toIndex < 0,
           fromIndex >= trackQueue.count,
           toIndex >= trackQueue.count,
           trackQueue[fromIndex] != track.SHA1
        {
            self.trackQueueSemaphore.signal()
            return false
        }
        self.trackQueue.remove(at: fromIndex)
        self.trackQueue.insert(track.SHA1, at: toIndex)
        self.trackQueueSemaphore.signal()
        return true
    }
    
    fileprivate func playingDone() {
        if let track = self.playingTrack {
            do {
                try historyWriter.writePlay(of: track.SHA1, at: Date())
            } catch {
                print("coudn't write history: \(error)")
            }
        }
        
        self.playingTrack = nil
        self.isPlaying = false
        self.player = nil
        print("calling serviceQueue from playingDone()")
        self.serviceQueue()
    }
    
    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        print("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");

        if index == -1,
           let playingTrack = playingTrack,
           playingTrack.SHA1 == sha1Hash
        {
            self.skip()
        } else {
            self.trackQueueSemaphore.wait()
            for (trackIndex, hash) in trackQueue.enumerated() {
                print("index \(trackIndex) hash \(sha1Hash)")
                if hash == sha1Hash,
                   index == trackIndex
                {
                    print("index \(index) needs to be removed")
                    self.trackQueue.remove(at: index)
                }
            }
            self.trackQueueSemaphore.signal()
        }
    }
    
    public func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        self.trackQueueSemaphore.wait()
        trackQueue.append(sha1Hash)
        self.trackQueueSemaphore.signal()
        print("calling serviceQueue from play")
        serviceQueue()
    }

    // skips the currently playing song, removing it from the playlist
    public func skip() {
        if let track = self.playingTrack {
            do {
                try historyWriter.writeSkip(of: track.SHA1, at: Date())
            } catch {
                print("coudn't write history: \(error)")
            }
            self.playingTrack = nil // set to keep skipped songs out of history (track these?)
        }
        if let player = self.player {
            self.player = nil
            player.pause()
        }
        playingDone()
    }

    public func pause() {
        if isPaused {
            isPaused = false
            self.player?.play()
        } else {
            print("calling pause isPaused \(isPaused)")
            isPaused = true
            self.player?.pause()
        }
    }
    
    public func resume() {
        self.pause()
    }

    @objc func playerDidFinishPlaying(note: NSNotification) {
        self.playingDone()
    }
    
    fileprivate func serviceQueue() {
        guard !isPlaying else { return }
        self.trackQueueSemaphore.wait()
        guard trackQueue.count > 0 else {
            self.trackQueueSemaphore.signal()
            return
        }
        let nextTrackHash = trackQueue.removeFirst()
        self.trackQueueSemaphore.signal()
        self.playingTrack = trackFinder.audioTrack(forHash: nextTrackHash)

        print("fuck self.playingTrack \(self.playingTrack)")
        
        isPlaying = true
        do {
            if let (_, url) = self.trackFinder.track(forHash: nextTrackHash) {
                print("about to play \(url)")
                let player = try AVPlayer(url: url)
                player.play()
                self.player = player
            }
        } catch {
            print("error \(error)")
        }
    }
}
