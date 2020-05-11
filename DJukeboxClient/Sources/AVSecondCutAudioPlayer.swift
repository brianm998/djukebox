import Foundation
import AVFoundation
import Dispatch
import DJukeboxCommon

// this class uses AVQueuePlayer to play remote audio urls locally
// while it can play more than one track in sequence while the app is in the background,
// it appears to fall into lower level bugs when playing subsequent tracks, oftentimes skipping back
// to the beginning of the song after the first 50 seconds.
// The second play then goes all the way to the end from the start.
public class AudioPlayer: NSObject, AudioPlayerType {

    public var isPlaying = false

    public var trackQueue: [String] {
        var ret: [String] = []

        var items = player.items()
        if items.count > 0 {
            items.removeFirst()
            for item in items {
                if let hash = trackMap[item.asset] {
                    ret.append(hash)
                }
            }
        }

        return ret
    }

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

    public var isPaused = false

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType
    
    let player = AVQueuePlayer(items: [])
    
    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType)
    {
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
        player.removeAllItems()
    }

    public func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        let queueFromIndex = fromIndex+1
        let queueToIndex = toIndex+1

        let items = player.items()
        
        if queueFromIndex < items.count,
           queueToIndex < items.count,
           queueFromIndex >= 0,
           queueToIndex >= 0
        {
            let itemToMove = items[queueFromIndex]
            let itemToPutAfter = items[queueToIndex-1]
            player.remove(itemToMove)
            player.insert(itemToMove, after: itemToPutAfter)
            return true
        }
        return false
    }
    
    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        if index == -1 {
            self.skip()
        } else {
            var items = player.items()
            let queueIndex = index+1
            if queueIndex < items.count {
                let item = items[queueIndex]
                if let hash = trackMap[item.asset],
                   let (track, _) = self.trackFinder.track(forHash: hash) ,
                   track.SHA1 == sha1Hash
                {
                    player.remove(item)
                }
            }
        }
    }

    private var trackMap: [AVAsset: String] = [:] // sha1 values
    
    public func play(sha1Hash: String) {
        if let (_, url) = self.trackFinder.track(forHash: sha1Hash) {
            let asset = AVAsset(url: url)
            player.insert(AVPlayerItem(asset: asset), after: nil)
            player.play()
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

    @objc func playerDidFinishPlaying(note: NSNotification) {
        Log.d("playerDidFinishPlaying")

        if let track = self.playingTrack {
            do {
                try historyWriter.writePlay(of: track.SHA1, at: Date())
            } catch {
                Log.d("coudn't write history: \(error)")
            }
        }

        // called every time each song finishes playing.
        // we could trim the trackMap here of already played tracks
    }
}
