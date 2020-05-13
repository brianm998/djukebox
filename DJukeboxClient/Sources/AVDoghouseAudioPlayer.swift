import Foundation
import AVFoundation
import Dispatch
import DJukeboxCommon

// this class uses AVQueuePlayer to play remote audio urls locally, keeping it in a doghouse.

// The 'doghouse' is that we only keep a single item in the AVQueuePlayer's queue at a time.
// this approach seems to avoid problems seen with other approaches, specifically running in the
// background properly, and playing each track fully without skipping back
public class AVDoghouseAudioPlayer: NSObject, AudioPlayerType {

    public var trackQueue: [String] = []

    public var playingTrack: AudioTrackType? {
        var items = player.items()
        if items.count > 0 {
            let first = items.removeFirst()
            if let hash = trackMap[first.asset],
               let (track, _) = self.trackFinder.track(forHash: hash) 
            {
                return track
            }
        }
        return nil
    }

    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval? { // ?? ?
        let currentTime = player.currentTime()
        // convert to seconds
        return Double(currentTime.value)/Double(currentTime.timescale)
    }

    public var playingTrackDuration: TimeInterval? {
        // The playback point, in seconds, within the timeline of the sound associated with the audio player.
        if let playingTrack = playingTrack { return playingTrack.timeInterval }
        return nil
    }

    public var isPaused = false {
        didSet(oldValue) {
            Log.i(isPaused)
            if isPaused {
                player.pause()
            } else {
                player.play()
            }
        }
    }

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType
    
    let player = AVQueuePlayer(items: [])
    
    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType)
    {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        
        super.init()

        player.automaticallyWaitsToMinimizeStalling = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerDidFinishPlaying),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: nil)

        // XXX testing
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in

            let currentTime = self.player.currentTime()

            // convert to seconds
            let seconds = Double(currentTime.value)/Double(currentTime.timescale)
            switch self.player.timeControlStatus {
            case .paused:
                Log.d("player rate \(self.player.rate) seconds \(seconds) paused")
            case .waitingToPlayAtSpecifiedRate:
                Log.d("player rate \(self.player.rate) seconds \(seconds) waitingToPlayAtSpecifiedRate")
            case .playing:
                Log.d("player rate \(self.player.rate) seconds \(seconds) playing")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func clearQueue() {
        player.removeAllItems()
        trackQueue = []
    }

    public func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        if fromIndex < 0,
           toIndex < 0,
           fromIndex >= trackQueue.count,
           toIndex >= trackQueue.count,
           trackQueue[fromIndex] != track.SHA1
        {
            return false
        }
        self.trackQueue.remove(at: fromIndex)
        self.trackQueue.insert(track.SHA1, at: toIndex)
        return true
    }
    
    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        Log.d("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");

        if index == -1,
           let playingTrack = playingTrack,
           playingTrack.SHA1 == sha1Hash
        {
            self.skip()
        } else {
            for (trackIndex, hash) in trackQueue.enumerated() {
                Log.d("index \(trackIndex) hash \(sha1Hash)")
                if hash == sha1Hash,
                   index == trackIndex
                {
                    Log.d("index \(index) needs to be removed")
                    self.trackQueue.remove(at: index)
                }
            }
        }
    }

    private var trackMap: [AVAsset: String] = [:] // sha1 values
    
    public func play(sha1Hash: String) {
        self.play(sha1Hash: sha1Hash, alwaysAdd: false)
    }
    
    public func play(sha1Hash: String, alwaysAdd: Bool = false) {
        if let (_, url) = self.trackFinder.track(forHash: sha1Hash) {
            let asset = AVAsset(url: url)
            if !alwaysAdd,
               let _ = self.playingTrack
            {
                trackQueue.append(sha1Hash)
            } else {
                player.insert(AVPlayerItem(asset: asset), after: nil)
                if !isPaused { player.play() }
            }
            trackMap[asset] = sha1Hash
        }
    }

    // skips the currently playing song, removing it from the playlist
    public func skip() {
        if let track = self.playingTrack {
            do {
                try historyWriter.writeSkip(of: track.SHA1, at: Date())
            } catch {
                Log.d("coudn't write history: \(error)")
            }
        }
        serviceQueue()
        player.advanceToNextItem()
    }

    public func pause() {
        if isPaused {
            isPaused = false
            self.player.play()
        } else {
            Log.d("calling pause isPaused \(isPaused)")
            isPaused = true
            self.player.pause()
        }
    }
    
    public func resume() {
        self.pause()
    }

    fileprivate func  serviceQueue() {
        if trackQueue.count > 0 {
            let nextTrack = trackQueue.removeFirst()
            self.play(sha1Hash: nextTrack, alwaysAdd: true)
        }
    }
    
    @objc func playerDidFinishPlaying(note: NSNotification) {
        Log.d("playerDidFinishPlaying")

        if let track = self.playingTrack {
            do {
                try historyWriter.writePlay(of: track.SHA1, at: Date())
            } catch {
                Log.d("coudn't write history: \(error)")
            }
        }

        serviceQueue()
        // called every time each song finishes playing.
        // we could trim the trackMap here of already played tracks
    }
}
