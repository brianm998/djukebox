import Vapor
import AVFoundation
import Dispatch

public protocol AudioPlayerType {
    var isPlaying: Bool { get }
    var trackQueue: [String] { get }
    var playingTrack: AudioTrack? { get }
    func play(sha1Hash: String)
    func stopPlaying(sha1Hash: String)
    func skip() 
    func pause() 
    func resume()
    func clearQueue()
}

public class LinuxAudioPlayer: NSObject, AudioPlayerType {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPlaying = false

    public var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType

    public var playingTrack: AudioTrack? 
    
    fileprivate var process: Process?
    
    init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
    }

    public func clearQueue() {
        trackQueue = []
    }

    fileprivate func playingDone() {
        self.playingTrack = nil
        self.isPlaying = false
        print("calling serviceQueue from playingDone()")
        self.serviceQueue()
    }
    
    public func stopPlaying(sha1Hash: String) {
        print("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");
        if let playingTrack = playingTrack,
           playingTrack.SHA1 == sha1Hash
        {
            self.skip()
        } else {
            for (index, hash) in trackQueue.enumerated() {
                print("index \(index) hash \(sha1Hash)")
                if hash == sha1Hash {
                    print("index \(index) needs to be removed")
                    if index == 0 {
                        trackQueue = Array(trackQueue[1..<trackQueue.count])
                    } else if index == trackQueue.count - 1 {
                        trackQueue = Array(trackQueue[0..<index])
                    } else if index < trackQueue.count {
                        trackQueue = Array(trackQueue[0..<index]) + Array(trackQueue[index+1..<trackQueue.count])
                    } else {
                        print("DOH")
                    }
                }
            }
        }
    }
    
    public func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        trackQueue.append(sha1Hash)
        print("calling serviceQueue from play")
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
        print("calling pause")
        if let process = self.process,
           process.isRunning
        {
            print("calling suspend on pid \(process.processIdentifier)")
            if process.suspend() {
                print("suspended properly?")
            } else {
                print("not suspended properly?")
            }
        } else {
            print("no process")
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
        guard !isPlaying else { return }
        let nextTrackHash = trackQueue.removeFirst()
        self.playingTrack = trackFinder.audioTrack(forHash: nextTrackHash)
        
        isPlaying = true
        dispatchQueue.async {
            do {
                if let (audioTrack, url) = self.trackFinder.track(forHash: nextTrackHash) {
                    print("playing \(audioTrack.Title)")
                    try self.play(filename: url.path)
                } else {
                    print("no track exists for hash \(nextTrackHash)")
                    // XXX throw missing value for hash
                }
            } catch {
                print("error \(error)")
            }
            print("linux calling playingDone")
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

// XXX this timer fires forever, and never ends
final class VaporTimer {
    let timer: DispatchSourceTimer
    let closure: () -> Void
    
    init(withMillisecondInterval interval: Int, closure: @escaping () -> Void) {
        self.closure = closure
        self.timer = DispatchSource.makeTimerSource()
        timer.setEventHandler(handler: self.closure)
        timer.schedule(deadline: .now() + .milliseconds(interval),
                       repeating: .milliseconds(interval),
                       leeway: .seconds(0))
        
        if #available(OSX 10.14.3,  *) {
            timer.activate()
        }
    }
}

public class MacAudioPlayer: NSObject, AudioPlayerType, AVAudioPlayerDelegate {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    public var isPlaying = false

    public var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType

    public var playingTrack: AudioTrack? 

    var vaporTimer: VaporTimer?
    
    var player: AVAudioPlayer? 
    
    init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
    }

    public func clearQueue() {
        trackQueue = []
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // XXX this delegate method never gets called :(
        print("song did finish")
        //playingDone()
    }

    fileprivate func playingDone() {
        self.playingTrack = nil
        self.isPlaying = false
        self.player = nil
        print("calling serviceQueue from playingDone()")
        self.serviceQueue()
    }
    
    public func stopPlaying(sha1Hash: String) {
        print("should stop playing \(sha1Hash) trackQueue.count \(trackQueue.count)");
        if let playingTrack = playingTrack,
           playingTrack.SHA1 == sha1Hash
        {
            self.skip()
        } else {
            for (index, hash) in trackQueue.enumerated() {
                print("index \(index) hash \(sha1Hash)")
                if hash == sha1Hash {
                    print("index \(index) needs to be removed")
                    if index == 0 {
                        trackQueue = Array(trackQueue[1..<trackQueue.count])
                    } else if index == trackQueue.count - 1 {
                        trackQueue = Array(trackQueue[0..<index])
                    } else if index < trackQueue.count {
                        trackQueue = Array(trackQueue[0..<index]) + Array(trackQueue[index+1..<trackQueue.count])
                    } else {
                        print("DOH")
                    }
                }
            }
        }
    }
    
    public func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        trackQueue.append(sha1Hash)
        print("calling serviceQueue from play")
        serviceQueue()
    }

    // skips the currently playing song, removing it from the playlist
    public func skip() {
        let player = self.player
        self.player = nil
        player?.stop()
        print("skip calling playingDone")
        playingDone()
    }

    fileprivate var isPaused = false
    
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
        guard trackQueue.count > 0 else { return }
        guard !isPlaying else { return }
        let nextTrackHash = trackQueue.removeFirst()
        self.playingTrack = trackFinder.audioTrack(forHash: nextTrackHash)
        
        isPlaying = true
        do {
            if let (audioTrack, url) = self.trackFinder.track(forHash: nextTrackHash) {
                print("about to play \(url)")
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.play()
                self.player = player
                print("player woot2 player.isPlaying \(player.isPlaying)")

                print("starting timer")

                if self.vaporTimer == nil {
                    self.vaporTimer = VaporTimer(withMillisecondInterval: 200) {
                        //print("vapor timer fired \(self.player) \(self.player?.isPlaying)")
                        if let player = self.player, !player.isPlaying, !self.isPaused {
                            print("vapor timer calling playingDone")
                            self.playingDone()
                        }
                    }
                }
            }
        } catch {
            print("error \(error)")
        }
    }

    fileprivate func play(filename: String) throws {
        // linux: aplay, osx: afplay
        var player: String = "afplay" 
        player = "aplay"
        let newProcess = Process()
       
        try shellOut(to: player,
                     arguments: ["\"\(filename)\""],
                     process: newProcess)
    }
}
