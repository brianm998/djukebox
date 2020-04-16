import Vapor

public protocol TrackFinderType {
    func track(forHash sha1Hash: String) -> (AudioTrack, String)?
    func filePath(forHash sha1Hash: String) -> String?
    func audioTrack(forHash sha1Hash: String) -> AudioTrack?
    func find(app: Application)
    var tracks: [String: (AudioTrack, [URL])] { get }
}

public class TrackFinder: TrackFinderType {

    public var tracks: [String: (AudioTrack, [URL])] = [:]

    public func track(forHash sha1Hash: String) -> (AudioTrack, String)? {
        if let (track, urls) = tracks[sha1Hash] {
            return (track, urls[0].path)
        } else {
            return nil
        }
    }
    
    public func filePath(forHash sha1Hash: String) -> String? {
        if let (_, urls) = tracks[sha1Hash] {
            return urls[0].path
        } else {
            return nil
        }
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrack? {
        if let (audioTrack, _) = tracks[sha1Hash] {
            return audioTrack
        } else {
            return nil
        }
    }
    
    public func find(app: Application) {
        find(at: URL(fileURLWithPath: "/mnt/tree/mp3/Yes"))
    }

    fileprivate func find(at url: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for url in urls {
                if url.hasDirectoryPath {
                    find(at: url)
                } else if url.absoluteString.hasSuffix(".json") {
                    let decoder = JSONDecoder()
                    let data = try Data(contentsOf: url)
                    let audioTrack = try decoder.decode(AudioTrack.self, from: data)

                    let trackUrl = url.deletingLastPathComponent()
                      .appendingPathComponent(audioTrack.Filename, isDirectory: false)

                    if try trackUrl.checkResourceIsReachable() {
                        if var (_, existingTracks) = tracks[audioTrack.SHA1] {
                            existingTracks.append(trackUrl)
                        } else {
                            tracks[audioTrack.SHA1] = (audioTrack, [trackUrl])
                        }
                    } else {
                        print("FAILED ON \(trackUrl)")
                    }
                }
            }
        } catch {
            print("DOH \(url)")
        }
    }    
}

let trackFinder = TrackFinder()

public class AudioPlayer {

    let dispatchQueue = DispatchQueue(label: "djukebox-audio-player")

    var isPlaying = false

    var trackQueue: [String] = []
    
    let trackFinder: TrackFinderType

    init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
    }

    func play(sha1Hash: String) {
        // XXX look up this hash beforehand, and throw error if not found?
        trackQueue.append(sha1Hash)
        serviceQueue()
    }

    func serviceQueue() {
        guard trackQueue.count > 0 else { return }
        guard !isPlaying else { return }

        let nextTrackHash = trackQueue.removeFirst()
        
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
            self.isPlaying = false
            self.serviceQueue()
        }

    }
    
    @discardableResult public func play(filename: String) throws -> Process {
        // linux: aplay, osx: afplay
        var player: String = "afplay" 
        #if os(Linux)
        player = "aplay"
        #endif
        let process = Process()
        try shellOut(to: player,
                     arguments: ["\"\(filename)\""],
                     process: process)
        return process
    }
}

let audioPlayer = AudioPlayer(trackFinder: trackFinder)

// configures your application
public func configure(_ app: Application) throws {

    trackFinder.find(app: app)

    //player.play(sha1Hash: "5e5a84c8657360dedf90664e1d615dcaa1fa4e21") // masquerade
    //player.play(sha1Hash: "6d9bf1732f616acab5adfbf4e27c08b037235e8b") // i would have waited forever

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
