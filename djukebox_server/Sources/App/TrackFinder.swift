import Vapor

public protocol TrackFinderType {
    func track(forHash sha1Hash: String) -> (AudioTrack, URL)?
    func filePath(forHash sha1Hash: String) -> String?
    func audioTrack(forHash sha1Hash: String) -> AudioTrack?
    func find(atFilePath path: String)
    var tracks: [String: (AudioTrack, [URL])] { get }
}

public class TrackFinder: TrackFinderType {

    public var tracks: [String: (AudioTrack, [URL])] = [:]

    public func track(forHash sha1Hash: String) -> (AudioTrack, URL)? {
        if let (track, urls) = tracks[sha1Hash] {
            return (track, urls[0])
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
    
    public func find(atFilePath path: String) {
        find(at: URL(fileURLWithPath: path))
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
            print("DOH \(url) \(error)")
        }
    }    
}

