import Foundation
import AVFoundation
import Dispatch
import os
import DJukeboxCommon

// this class uses AVQueuePlayer to play remote audio urls locally, keeping it in a doghouse.

// The 'doghouse' is that we only keep a single item in the AVQueuePlayer's queue at a time.
// this approach seems to avoid problems seen with other approaches, specifically running in the
// background properly, and playing each track fully without skipping back
// @unchecked Sendable: an AudioPlayerType (a non-isolated DJukeboxCommon protocol).
// Playback runs through a single AVQueuePlayer and the queue/trackMap mutations are
// driven from the main thread: AVFoundation's end-of-item and failure signals hop
// there first. See the client concurrency note in AsyncAudioPlayer.
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
    
    // The playback point, in seconds, within the current item; nil when there is
    // none to report (no item, or one that hasn't loaded yet).
    public var playingTrackPosition: TimeInterval? {
        get {
            let currentTime = player.currentTime()
            guard currentTime.isValid, currentTime.isNumeric else { return nil }
            let seconds = CMTimeGetSeconds(currentTime)
            return seconds.isFinite ? seconds : nil
        }
        set(newValue) {
            if let newValue, newValue.isFinite {
                let seekTime = CMTime(seconds: newValue, preferredTimescale: 600)
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
        if let playingTrack { return playingTrack.timeInterval }
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

    let trackFinder: TrackCatalog

    let historyWriter: HistoryWriterType

    // One PlaybackGain per AVPlayerItem (each drives its own MTAudioProcessingTap),
    // so a track's boost can never bleed into the next during the queue handoff.
    // Guarded by a lock because it is touched from the main thread (play / live
    // preview) and the end-of-item notification thread. Local streaming playback
    // is boosted above unity here (AVPlayer.volume can't).
    private let itemGains = OSAllocatedUnfairLock(initialState: [AVPlayerItem: PlaybackGain]())

    private func setGain(_ gain: PlaybackGain, for item: AVPlayerItem) {
        itemGains.withLock { $0[item] = gain }
    }
    private func gain(for item: AVPlayerItem) -> PlaybackGain? {
        itemGains.withLock { $0[item] }
    }
    private func forgetGain(for item: AVPlayerItem) {
        itemGains.withLock { $0[item] = nil }
    }
    private func forgetAllGains() {
        itemGains.withLock { $0.removeAll() }
    }

    // drop everything remembered about an item that is leaving the player
    private func forget(_ item: AVPlayerItem) {
        forgetGain(for: item)
        trackMap[item] = nil
        statusObservations[item] = nil
    }

    // Looks up a track's saved gain (dB) from the server; injected so this player
    // stays decoupled from the networking layer. play() (part of the synchronous,
    // non-isolated AudioPlayerType shared with the server) can't itself await this,
    // so applySavedGain() below fires it in its own Task; nil => everything at unity.
    let savedGainForHash: (@Sendable (String) async -> Double)?

    // Consumes AVPlayerItemDidPlayToEndTime via `for await` instead of an @objc
    // selector; cancelled in deinit (Task is Sendable, unlike a Notification
    // observer token, so this needs no nonisolated(unsafe) escape hatch).
    private var endOfItemTask: Task<Void, Never>?

    // Same for AVPlayerItemFailedToPlayToEndTime. An item that can't even load
    // never posts it, so each item's status is observed too (statusObservations).
    private var failedItemTask: Task<Void, Never>?
    private var statusObservations: [AVPlayerItem: NSKeyValueObservation] = [:]

    // Shared VU-meter sink handed to every item's gain tap, so the tap that's
    // currently rendering publishes per-channel output levels. Injected by Client
    // so the same meter feeds the AudioLevelMonitor driving the tubes.
    public let levelMeter: AudioLevelMeter

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
    
    public init(trackFinder: TrackCatalog,
                historyWriter: HistoryWriterType,
                savedGainForHash: (@Sendable (String) async -> Double)? = nil,
                levelMeter: AudioLevelMeter = AudioLevelMeter())
    {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        self.savedGainForHash = savedGainForHash
        self.levelMeter = levelMeter

        super.init()

        player.automaticallyWaitsToMinimizeStalling = true
        let notifications = NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime)
        self.endOfItemTask = Task { [weak self] in
            for await note in notifications {
                guard let self else { return }
                await self.playerDidFinishPlaying(note: note)
            }
        }
        let failures = NotificationCenter.default.notifications(named: .AVPlayerItemFailedToPlayToEndTime)
        self.failedItemTask = Task { [weak self] in
            for await note in failures {
                guard let self else { return }
                await self.playerDidFailToPlay(note: note)
            }
        }

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
        endOfItemTask?.cancel()
        failedItemTask?.cancel()
    }
    
    public func clearQueue() {
        player.removeAllItems()
        trackQueue = []
        trackMap = [:]
        statusObservations = [:]
        forgetAllGains()
        levelMeter.reset()
    }

    // Both indexes must be inside the queue. The caller's list can be stale (the
    // queue advances underneath it), so a fromIndex that now holds another track
    // is resolved by hash; false if the track is no longer queued.
    public func move(track: AudioTrackType, fromIndex: Int, toIndex: Int) -> Bool {
        guard trackQueue.indices.contains(fromIndex),
              trackQueue.indices.contains(toIndex),
              let index = queueIndex(of: track.SHA1, expectedAt: fromIndex)
        else { return false }
        trackQueue.remove(at: index)
        trackQueue.insert(track.SHA1, at: toIndex)
        return true
    }
    
    // An index of -1 means the playing track. Any other index is a queue position,
    // resolved by hash if it is stale.
    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        Log.d("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");

        if index == -1 {
            if playingTrack?.SHA1 == sha1Hash {
                self.skip()
            }
        } else if index >= 0,
                  let queueIndex = queueIndex(of: sha1Hash, expectedAt: index)
        {
            Log.d("index \(queueIndex) needs to be removed")
            trackQueue.remove(at: queueIndex)
        }
    }

    // where this hash is in trackQueue: the expected index if it still matches,
    // otherwise its first occurrence
    private func queueIndex(of sha1Hash: String, expectedAt index: Int) -> Int? {
        if trackQueue.indices.contains(index),
           trackQueue[index] == sha1Hash
        {
            return index
        }
        return trackQueue.firstIndex(of: sha1Hash)
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
                trackMap[item] = sha1Hash
                observeStatus(of: item)   // before insert, which starts the load
                player.insert(item, after: nil)
                let gain = PlaybackGain(levelMeter: levelMeter)   // fresh => unity until the saved value arrives
                setGain(gain, for: item)
                attachGain(to: item, asset: asset, gain: gain)
                applySavedGain(gain, forHash: sha1Hash)
                if !isPaused { startPlayer() }
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservations[item] = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            // KVO fires on AVFoundation's thread; hop like the notifications do
            let itemBox = UncheckedSendableBox(item)
            Task { @MainActor in
                self?.itemDidFail(itemBox.value)
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
        guard let savedGainForHash else { return }
        Task {
            let db = await savedGainForHash(sha1Hash)
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
        let skipped = player.items().first
        serviceQueue()
        player.advanceToNextItem()
        if let skipped { forget(skipped) }
    }

    fileprivate func seek(to time: CMTime) {
        // nothing to seek once the queue is cleared; without this the retry below
        // would run forever and keep a replaced player alive
        guard !player.items().isEmpty else { return }
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
    
    // Resume playback if paused; a no-op if already playing. NOT a toggle (pause()
    // handles pausing) so it's safe to call after enqueuing a user-tapped track to
    // ensure playback actually starts even when the player was restored paused.
    public func resume() {
        if isPaused {
            isPaused = false
            self.startPlayer()
        }
    }

    // Hand the player the next queued track, dropping any hash that no longer
    // resolves to a URL: stopping at one would leave the doghouse empty for good.
    fileprivate func  serviceQueue() {
        let itemCount = player.items().count
        while !trackQueue.isEmpty && player.items().count == itemCount {
            let nextTrack = trackQueue.removeFirst()
            self.play(sha1Hash: nextTrack, alwaysAdd: true)
        }
    }
    
    // AVFoundation posts this on its own thread, but everything the handler
    // touches is main-thread state: trackQueue/trackMap, AVPlayerItem creation in
    // play() (main-actor isolated, see trackMap's comment), and the local track
    // catalog behind trackFinder — hop over before touching any of it.
    private func playerDidFinishPlaying(note: Notification) async {
        let finishedBox = UncheckedSendableBox(note.object as? AVPlayerItem)
        await MainActor.run {
            Log.d("playerDidFinishPlaying")

            // resolve the played track from the finished item itself (we drop it
            // from trackMap just below, and playingTrack can't be trusted here).
            if let finished = finishedBox.value,
               let hash = self.trackMap[finished]
            {
                do {
                    try self.historyWriter.writePlay(of: hash, at: Date())
                } catch {
                    Log.d("coudn't write history: \(error)")
                }
            }

            // Drop the finished item ourselves. An AVQueuePlayer only removes an
            // item when it ADVANCES to a following one, but the doghouse only ever
            // holds a SINGLE item — so a finished track just stays as currentItem
            // (parked at its end) and items() never empties on its own. That made
            // the isEmpty guard below never fire, so the queue never auto-advanced
            // and local/offline playback stopped dead after one track. Its gain tap
            // is torn down with it and nothing looks up a played item again.
            if let finished = finishedBox.value {
                self.player.remove(finished)
                self.forget(finished)
            }

            // Now refill from the doghouse queue — unless a play() already slipped
            // an item in during the finish-to-hop gap (then it's already playing
            // the right thing and a second insert would break the one-item
            // invariant for good).
            if self.player.items().isEmpty {
                self.serviceQueue()
                // A track just played to its end, so keep playing the next one.
                // serviceQueue() enqueues it, but play()'s `if !isPaused` gate can
                // leave it sitting silently at position NaN (auto-advance, unlike a
                // user tap, never calls resume()). Setting isPaused fires
                // startPlayer() via its didSet and keeps play/pause state correct.
                if !self.player.items().isEmpty {
                    self.isPaused = false
                }
            }
        }
    }

    private func playerDidFailToPlay(note: Notification) async {
        let failedBox = UncheckedSendableBox(note.object as? AVPlayerItem)
        await MainActor.run {
            if let failed = failedBox.value {
                self.itemDidFail(failed)
            }
        }
    }

    // Drop an item that can't be played and move on, else it stays the single
    // doghouse item forever. Both failure signals can arrive for one item, and
    // other players' items post here too: only an item still in trackMap counts.
    // No play history is written for it. Main thread only.
    private func itemDidFail(_ item: AVPlayerItem) {
        guard let hash = trackMap[item] else { return }
        Log.w("couldn't play \(hash): \(String(describing: item.error))")

        player.remove(item)
        forget(item)

        if player.items().isEmpty {
            seekTime = nil   // any pending seek was meant for the failed track
            serviceQueue()
            if !player.items().isEmpty && !isPaused {
                startPlayer()
            }
        }
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
