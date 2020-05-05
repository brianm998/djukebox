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
    public var playingTrackDuration: TimeInterval? {
        //if let player = player { return player.duration } // XXX XXX FIX THIS
        return nil
    }

    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval? {
        // if let player = player { return player.currentTime } /// XXX XXX FIX THIS TOO (maybe it can work?)
        return nil
    }

    public var isPaused = false

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType
    
    var vaporTimer: VaporTimer?
    
    var player: AVPlayer? 
    
    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType) {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
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
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // XXX this delegate method never gets called :(
        print("song did finish")
        //playingDone()
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
        print("calling pause")
        isPaused = true
        self.player?.pause()
    }
    
    public func resume() {
        self.player?.play()
        isPaused = false
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
                //player.delegate = self
                player.play()
                self.player = player
                //print("player woot2 player.isPlaying \(player.isPlaying)")

                print("starting timer")

                if self.vaporTimer == nil {
                    self.vaporTimer = VaporTimer(withMillisecondInterval: 200) {
                        //print("vapor timer fired \(self.player) player.currentItem \(player.currentItem)")
                        if let player = self.player,
                           //   !player.isPlaying,
                           player.currentItem == nil,
                           !self.isPaused
                        {
                            print("vapor timer calling playingDone")
                            self.playingDone()
                        } else {
                            print("player.currentItem \(player.currentItem) self.playingTrack \(self.playingTrack) trackQueue \(self.trackQueue)")
                        }
                    }
                }
            }
        } catch {
            print("error \(error)")
        }
    }
}
