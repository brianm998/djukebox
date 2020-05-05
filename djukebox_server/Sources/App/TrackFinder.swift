import Vapor
import DJukeboxCommon

public class TrackFinder: TrackFinderType {

    public var tracks: [String: (AudioTrackType, [URL])] = [:]

    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let (track, urls) = tracks[sha1Hash] {
            return (track, urls[0])
        } else {
            return nil
        }
    }

    public func tracks(forArtist artist: String) -> [String: (AudioTrackType, [URL])] {
        var ret: [String: (AudioTrackType, [URL])] = [:]
        for (hash, (track, urls)) in tracks {
            if track.Artist == artist {
                ret[hash] = (track, urls)
            }
        }
        return ret
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
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

