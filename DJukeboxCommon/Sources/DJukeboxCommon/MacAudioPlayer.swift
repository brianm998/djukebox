import Foundation
import AVFoundation
import Dispatch

// @unchecked Sendable: a process-wide singleton audio player. Its queue mutations
// are guarded by `trackQueueSemaphore`; the remaining playback state is only
// touched from the serial audio dispatch queue / the node completion callback.
// Kept unchecked so the server can hold it in a global `any AudioPlayerType & Sendable`.
//
// Playback runs through an AVAudioEngine graph — playerNode -> eq -> mainMixer —
// rather than a bare AVAudioPlayer, because AVAudioPlayer.volume is clamped to
// 0...1 (it can only attenuate). The AVAudioUnitEQ's globalGain accepts up to
// +24 dB, which is what lets us actually make quiet tracks louder. The per-track
// gain is supplied by the injected `volumeSource` (backed by the database) and
// applied the moment a track starts.
public final class MacAudioPlayer: AudioPlayerType, @unchecked Sendable {
    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPlaying = false

    public var trackQueue: [String] = []

    fileprivate var trackQueueSemaphore = DispatchSemaphore(value: 1)

    public var playingTrack: AudioTrackType?

    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackDuration: TimeInterval? {
        guard let audioFile = audioFile else { return nil }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    // The playback point, in seconds, within the timeline of the sound currently
    // playing. The player node's sample clock is reset (via stop()) at the start
    // of every track, so this is a per-track offset, and it freezes across pause.
    public var playingTrackPosition: TimeInterval? {
        get {
            guard playingTrack != nil,
                  let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
                  playerTime.sampleRate > 0
            else { return nil }
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
        set(newValue) {
            Log.w("seeking is unimplemented")
        }
    }

    public var isPaused = false

    let trackFinder: TrackFinderType

    let historyWriter: HistoryWriterType

    // Supplies the per-track gain (dB) to apply. Injected so this shared type
    // stays independent of the server's database. nil => everything at unity.
    let volumeSource: VolumeAdjustmentSource?

    // The audio graph, created once and reused across tracks.
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 0)   // globalGain only

    // The file currently scheduled on the player node (nil when nothing plays).
    private var audioFile: AVAudioFile?

    // Bumped on every track start; the scheduled-file completion callback captures
    // its generation and only advances the queue if it still matches, so a skip()
    // (or a rapid next-track) can't be double-counted by a stale callback.
    private var playGeneration = 0

    public init(trackFinder: TrackFinderType,
                historyWriter: HistoryWriterType,
                volumeSource: VolumeAdjustmentSource? = nil) {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        self.volumeSource = volumeSource
        engine.attach(playerNode)
        engine.attach(eq)
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
                Log.e("coudn't write history: \(error)")
            }
        }

        self.playingTrack = nil
        self.isPlaying = false
        self.audioFile = nil
        Log.d("calling serviceQueue from playingDone()")
        self.serviceQueue()
    }

    public func stopPlaying(sha1Hash: String, atIndex index: Int) {
        Log.d("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");
        self.trackQueueSemaphore.wait()
        for (trackIndex, hash) in trackQueue.enumerated() {
            Log.d("index \(trackIndex) hash \(sha1Hash)")
            if hash == sha1Hash,
               index == trackIndex
            {
                Log.d("index \(index) needs to be removed")
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
        Log.d("calling serviceQueue from play")
        // AVAudioEngine graph mutation is not thread-safe: funnel every engine /
        // node operation through the serial dispatchQueue (the completion callback
        // dispatches here too), so the graph is only ever touched from one thread.
        dispatchQueue.async { [weak self] in self?.serviceQueue() }
    }

    // skips the currently playing song, removing it from the playlist
    public func skip() {
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            if let track = self.playingTrack {
                do {
                    try self.historyWriter.writeSkip(of: track.SHA1, at: Date())
                } catch {
                    Log.d("coudn't write history: \(error)")
                }
                self.playingTrack = nil // keep skipped songs out of history (track these?)
            }
            // invalidate any in-flight completion callback before stopping the node
            self.playGeneration &+= 1
            self.playerNode.stop()
            self.audioFile = nil
            self.playingDone()
        }
    }

    public func pause() {
        Log.d("calling pause")
        isPaused = true
        dispatchQueue.async { [weak self] in self?.playerNode.pause() }
    }

    public func resume() {
        isPaused = false
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.engine.isRunning { try? self.engine.start() }
            self.playerNode.play()
        }
    }

    // must be called on dispatchQueue (see play()/skip()/the completion callback)
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

        isPlaying = true
        do {
            if let (_, url) = self.trackFinder.track(forHash: nextTrackHash) {
                Log.d("about to play \(url)")
                let file = try AVAudioFile(forReading: url)

                // resolve and apply this track's gain (track > album > artist).
                // globalGain is in dB and clamped by AVAudioUnitEQ to -96...24.
                let gainDB = volumeSource?.gainDecibels(forHash: nextTrackHash) ?? 0
                eq.globalGain = Float(max(-96, min(24, gainDB)))
                if gainDB != 0 { Log.d("applying \(gainDB) dB gain to \(nextTrackHash)") }

                // (re)wire the graph for this file's format, then make sure the
                // engine is running. Reset the node first so its sample clock —
                // which drives playingTrackPosition — starts at 0 for this track.
                playerNode.stop()
                let format = file.processingFormat
                engine.connect(playerNode, to: eq, format: format)
                engine.connect(eq, to: engine.mainMixerNode, format: format)
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }

                self.audioFile = file
                self.isPaused = false

                let generation = self.playGeneration
                playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard let self = self else { return }
                    self.dispatchQueue.async {
                        // .dataPlayedBack only fires on genuine end-of-track (pause
                        // suspends rendering, it does not "play back" the data), so
                        // the generation counter alone is the right guard: a stale
                        // callback after skip() / next-track has a bumped generation.
                        // We must NOT gate on isPaused — a completion racing with a
                        // just-issued pause would otherwise be swallowed and stall
                        // the queue forever.
                        guard generation == self.playGeneration else { return }
                        Log.d("scheduled file finished; advancing queue")
                        self.playingDone()
                    }
                }
                playerNode.play()
                Log.d("player playing \(playerNode.isPlaying)")
            }
        } catch {
            Log.e("error \(error)")
            // don't wedge the queue on a bad file — drop it and try the next one
            self.isPlaying = false
            self.playingTrack = nil
            self.audioFile = nil
        }
    }

    public func shuffleQueue() {
        trackQueue.shuffle()
    }

    // Live "audition": change the currently-playing track's gain right now. The
    // EQ's globalGain can be updated mid-playback, so this takes effect immediately
    // (unlike the persisted adjustment, which the next serviceQueue applies). The
    // next track start overwrites it with that track's saved gain.
    public func setLivePlaybackGain(decibels: Double) {
        dispatchQueue.async { [weak self] in
            self?.eq.globalGain = Float(max(-96, min(24, decibels)))
        }
    }
}
