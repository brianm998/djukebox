import Foundation
import AVFoundation
import Dispatch
import DJukeboxCommon

// this class uses AVQueuePlayer to play remote audio urls locally, keeping it in a doghouse.

// The 'doghouse' is that we only keep a single item in the AVQueuePlayer's queue at a time.
// this approach seems to avoid problems seen with other approaches, specifically running in the
// background properly, and playing each track fully without skipping back
// @unchecked Sendable: an AudioPlayerType (a non-isolated DJukeboxCommon protocol).
// Playback runs through a single AVQueuePlayer and the queue/trackMap mutations are
// driven from the main thread and AVFoundation's end-of-item notification. See the
// client concurrency note in AsyncAudioPlayer.
public class AVDoghouseAudioPlayer: NSObject, AudioPlayerType, @unchecked Sendable {

    public var trackQueue: [String] = []

    public var playingTrack: AudioTrackType? {
        var items = player.items()
        if items.count > 0 {
            let first = items.removeFirst()
            if let hash = trackMap[first],
               let (track, _) = self.trackFinder.track(forHash: hash)
            {
                return track
            }
        }
        return nil
    }

    var seekTime: CMTime?
    
    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval? { // ?? ?
        get {
            let currentTime = player.currentTime()
            // convert to seconds
            return Double(currentTime.value)/Double(currentTime.timescale)
        }
        set(newValue) {
            if let newValue = newValue {
                let seekTime = CMTime(value: Int64(newValue), timescale: 1)
                self.logPlayerStatus()
                Log.i("trying to seek to \(seekTime)")
                if player.timeControlStatus == .paused {
                    // keep the seek time around for later
                    self.seekTime = seekTime
                } else {
                    self.seek(to: seekTime)
                }
            }
        }
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
                startPlayer()
            }
        }
    }

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType

    // One PlaybackGain per AVPlayerItem (each drives its own MTAudioProcessingTap),
    // so a track's boost can never bleed into the next during the queue handoff.
    // Guarded by a lock because it is touched from the main thread (play / live
    // preview) and the end-of-item notification thread. Local streaming playback
    // is boosted above unity here (AVPlayer.volume can't).
    private var itemGains: [AVPlayerItem: PlaybackGain] = [:]
    private let itemGainsLock = NSLock()

    private func setGain(_ gain: PlaybackGain, for item: AVPlayerItem) {
        itemGainsLock.lock(); itemGains[item] = gain; itemGainsLock.unlock()
    }
    private func gain(for item: AVPlayerItem) -> PlaybackGain? {
        itemGainsLock.lock(); defer { itemGainsLock.unlock() }; return itemGains[item]
    }
    private func forgetGain(for item: AVPlayerItem) {
        itemGainsLock.lock(); itemGains[item] = nil; itemGainsLock.unlock()
    }
    private func forgetAllGains() {
        itemGainsLock.lock(); itemGains.removeAll(); itemGainsLock.unlock()
    }

    // Looks up a track's saved gain (dB) from the server; injected so this player
    // stays decoupled from the networking layer. Invoked on the main thread from
    // play(). nil => everything at unity.
    let savedGainForHash: ((String, @escaping (Double) -> Void) -> Void)?

    let player = AVQueuePlayer(items: [])

    fileprivate func logPlayerStatus() {
        switch player.timeControlStatus {
        case .paused:
            Log.i("paused")
        case .waitingToPlayAtSpecifiedRate:
            Log.i("waitingToPlayAtSpecifiedRate")
        case .playing:
            Log.i("playing")
        default:
            Log.i("unknown default")
        }
    }
    
    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType,
                savedGainForHash: ((String, @escaping (Double) -> Void) -> Void)? = nil)
    {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        self.savedGainForHash = savedGainForHash

        super.init()
        
        player.automaticallyWaitsToMinimizeStalling = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerDidFinishPlaying),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: nil)

        /*
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
*/
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func clearQueue() {
        player.removeAllItems()
        trackQueue = []
        forgetAllGains()
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

    // Keyed by the player item (object identity) rather than its AVAsset: AVAsset
    // is non-Sendable and AVPlayerItem.init(asset:) is main-actor isolated, so
    // handing the asset off to the item and keying the map on the item avoids a
    // non-Sendable value living in two isolation regions at once.
    private var trackMap: [AVPlayerItem: String] = [:] // sha1 values

    public func play(sha1Hash: String) {
        self.play(sha1Hash: sha1Hash, alwaysAdd: false)
    }

    public func play(sha1Hash: String, alwaysAdd: Bool = false) {
        if let (_, url) = self.trackFinder.track(forHash: sha1Hash) {
            if !alwaysAdd,
               let _ = self.playingTrack
            {
                trackQueue.append(sha1Hash)
            } else {
                let asset = AVURLAsset(url: url)
                let item = AVPlayerItem(asset: asset)
                player.insert(item, after: nil)
                trackMap[item] = sha1Hash
                let gain = PlaybackGain()   // fresh => unity until the saved value arrives
                setGain(gain, for: item)
                attachGain(to: item, asset: asset, gain: gain)
                applySavedGain(gain, forHash: sha1Hash)
                if !isPaused { startPlayer() }
            }
        }
    }

    // Attach a gain tap to this item's audio. Tracks load asynchronously (the URL
    // is a remote stream), so the mix is set once the audio track is available.
    private func attachGain(to item: AVPlayerItem, asset: AVURLAsset, gain: PlaybackGain) {
        // AVPlayerItem / AVAudioMix are non-Sendable but we only ever touch them
        // on the main thread; box them to cross the load callback safely.
        let itemBox = UncheckedSendableBox(item)
        asset.loadTracks(withMediaType: .audio) { tracks, _ in
            guard let track = tracks?.first else { return }
            let mixBox = UncheckedSendableBox(gain.makeAudioMix(for: track))
            DispatchQueue.main.async {
                itemBox.value.audioMix = mixBox.value
            }
        }
    }

    // A fresh PlaybackGain is already unity, so there's nothing to reset — just
    // apply this track's saved gain to ITS OWN gain object when the server
    // responds (a few ms on the LAN). Setting it is thread-safe (locked).
    private func applySavedGain(_ gain: PlaybackGain, forHash sha1Hash: String) {
        savedGainForHash?(sha1Hash) { db in
            gain.setDecibels(db)
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

    fileprivate func seek(to time: CMTime) {
        self.logPlayerStatus()
        if self.player.timeControlStatus == .playing {
            self.player.seek(to: time) { success in
                self.seekTime = nil
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.seek(to: time)
            }
        }
    }
    
    fileprivate func startPlayer() {
        Log.i()
        DispatchQueue.main.async {
            self.logPlayerStatus()
            self.player.play()
            if let seekTime = self.seekTime {
                Log.i("trying to seek to \(seekTime)")

                self.seek(to: seekTime)
            }
        }
    }
    
    public func pause() {
        if isPaused {
            isPaused = false
            self.startPlayer()
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
        // drop the finished item's gain (its tap is torn down with the item)
        if let finished = note.object as? AVPlayerItem {
            forgetGain(for: finished)
        }
        // called every time each song finishes playing.
        // we could trim the trackMap here of already played tracks
    }

    public func shuffleQueue() {
        trackQueue.shuffle()
    }

    // Live "audition": change the CURRENT track's gain right now (its tap picks it
    // up on the next audio buffer). Overrides the AudioPlayerType no-op default.
    public func setLivePlaybackGain(decibels: Double) {
        guard let item = player.currentItem, let gain = gain(for: item) else { return }
        gain.setDecibels(decibels)
    }
}
