import Vapor

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

public class AudioPlayer: AudioPlayerType {

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
                if let (audioTrack, filename) = self.trackFinder.track(forHash: nextTrackHash) {
                    print("playing \(audioTrack.Title)")
                    try self.play(filename: filename)
                } else {
                    //throw "no track exists for hash \(sha1Hash)"
                    // XXX throw missing value for hash
                }
            } catch {
                print("error \(error)")
            }
            self.playingTrack = nil
            self.isPlaying = false
            self.serviceQueue()
        }
    }

    fileprivate func play(filename: String) throws {
        // linux: aplay, osx: afplay
        var player: String = "afplay" 
        #if os(Linux)
        player = "aplay"
        #endif
        let newProcess = Process()
        self.process = newProcess
        try shellOut(to: player,
                     arguments: ["\"\(filename)\""],
                     process: newProcess)
    }
}

