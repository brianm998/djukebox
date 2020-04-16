import Vapor

public class AudioPlayer {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    var isPlaying = false

    var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType

    var playingTrack: AudioTrack? 
    
    init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
    }

    func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        trackQueue.append(sha1Hash)
        serviceQueue()
    }

    func stopCurrent() {
        if let process = self.process,
           process.isRunning
        {
            process.terminate()
            self.process = nil
        }
    }
    
    func pause() {
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
    
    func resume() {
        if let process = self.process,
           process.isRunning
        {
            process.resume()
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

    fileprivate var process: Process?
    
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

