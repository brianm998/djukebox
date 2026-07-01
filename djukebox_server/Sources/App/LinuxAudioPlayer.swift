import Foundation
import DJukeboxCommon

// @unchecked Sendable: a process-wide singleton audio player whose playback work
// is serialized on its private `dispatchQueue`. Held by the server in a global
// `any AudioPlayerType & Sendable`.
public final class LinuxAudioPlayer: AudioPlayerType, @unchecked Sendable {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPaused = true

    public var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType
    let historyWriter: HistoryWriter // not written to in linux yet

    // Supplies the per-track gain (dB) to apply; injected so playback can boost
    // quiet tracks. nil => everything plays at its recorded level.
    let volumeSource: VolumeAdjustmentSource?

    public var playingTrack: AudioTrackType?

    // XXX implement this for linux
    // The total duration, in seconds, of the sound associated with the audio player.
    public var playingTrackDuration: TimeInterval?

    // XXX implement this for linux
    // The playback point, in seconds, within the timeline of the sound associated with the audio player.
    public var playingTrackPosition: TimeInterval?

    fileprivate var process: Process?
    
    init(trackFinder: TrackFinderType,
         historyWriter: HistoryWriter,
         volumeSource: VolumeAdjustmentSource? = nil) {
        self.trackFinder = trackFinder
        self.historyWriter = historyWriter
        self.volumeSource = volumeSource
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
                    let gainDB = self.volumeSource?.gainDecibels(forHash: nextTrackHash) ?? 0
                    Log.d("playing \(audioTrack.Title) (gain \(gainDB) dB)")
                    try self.play(filename: url.path, gainDecibels: gainDB)
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

    fileprivate func play(filename: String, gainDecibels: Double = 0) throws {
        let newProcess = Process()
        self.process = newProcess
        // ffplay decodes mp3 (which aplay cannot) and its ffmpeg "volume" filter
        // accepts a decibel gain directly, so it doubles as our boost mechanism.
        // Requires ffmpeg's ffplay on the server's PATH.
        var arguments = ["-nodisp", "-autoexit", "-loglevel", "quiet"]
        if gainDecibels != 0 {
            arguments += ["-af", "volume=\(gainDecibels)dB"]
        }
        arguments.append("\"\(filename)\"")
        try shellOut(to: "ffplay",
                     arguments: arguments,
                     process: newProcess)
    }

    public func shuffleQueue() {
        trackQueue.shuffle()
    }
}
