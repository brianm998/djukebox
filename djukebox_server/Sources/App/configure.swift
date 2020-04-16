import Vapor

public class TrackFinder {

    var tracks: [String: (AudioTrack, [URL])] = [:]

    func filePath(forHash sha1Hash: String) -> String? {
        if let (_, urls) = tracks[sha1Hash] {
            return urls[0].path
        } else {
            return nil
        }
    }
    
    func audioTrack(forHash sha1Hash: String) -> AudioTrack? {
        if let (audioTrack, _) = tracks[sha1Hash] {
            return audioTrack
        } else {
            return nil
        }
    }
    
    func find(app: Application) {
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

// configures your application
public func configure(_ app: Application) throws {

    //trackFinder.find(app: app)

    let dir = "/mnt/root/mp3/Zero_Gravity/Space_Does_Not_Care"

    let track1 = "Zero_Gravity=Space_Does_Not_Care=08=Precognition.mp3"
    let track2 = "Zero_Gravity=Space_Does_Not_Care=04=Interferon.mp3"
    

    do {
        print("playing \(track1)")
        try play(filename: "\(dir)/\(track1)")
        print("playing \(track2)")
        try play(filename: "\(dir)/\(track2)")
    } catch {
        print("DOH \(error)")
    }


    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
