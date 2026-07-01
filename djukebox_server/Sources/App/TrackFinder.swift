import Vapor
import DJukeboxCommon

// @unchecked Sendable: the catalog dictionary is guarded by `lock`. It is
// populated by reconcile()/ingest()/find() (startup and the /discover endpoint)
// and only read by the request handlers.
public final class TrackFinder: TrackFinderType, @unchecked Sendable {

    private let lock = NSLock()
    private var _tracks: [String: (AudioTrackType, [URL])] = [:]

    /// A snapshot of the whole catalog, copied under the lock. Callers that need
    /// only one track should prefer the `…(forHash:)` accessors, which don't copy.
    public var tracks: [String: (AudioTrackType, [URL])] {
        get { lock.lock(); defer { lock.unlock() }; return _tracks }
        set { lock.lock(); defer { lock.unlock() }; _tracks = newValue }
    }

    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        lock.lock(); defer { lock.unlock() }
        if let (track, urls) = _tracks[sha1Hash] {
            return (track, urls[0])
        } else {
            return nil
        }
    }

    public func tracks(forArtist artist: String) -> [String: (AudioTrackType, [URL])] {
        lock.lock(); defer { lock.unlock() }
        var ret: [String: (AudioTrackType, [URL])] = [:]
        for (hash, (track, urls)) in _tracks {
            if track.Artist == artist {
                ret[hash] = (track, urls)
            }
        }
        return ret
    }

    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
        lock.lock(); defer { lock.unlock() }
        if let (audioTrack, _) = _tracks[sha1Hash] {
            return audioTrack
        } else {
            return nil
        }
    }
    
    public func find(atFilePath path: String) {
        find(at: URL(fileURLWithPath: path))
    }

    fileprivate func find(at url: URL) {
        Log.d("find at: \(url.absoluteString)")
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for url in urls {
                if url.hasDirectoryPath {
                    find(at: url)
                } else if url.absoluteString.hasSuffix(".json") {
                    Log.d("path \(url.absoluteString)")
                    let decoder = JSONDecoder()
                    do {
                        let data = try Data(contentsOf: url)
                        let audioTrack = try decoder.decode(AudioTrack.self, from: data).sanitized
                        
                        let trackUrl = url.deletingLastPathComponent()
                          .appendingPathComponent(audioTrack.Filename, isDirectory: false)

                        if try trackUrl.checkResourceIsReachable() {
                            // NOTE: previously `if var (_, existingTracks) =
                            // tracks[...] { existingTracks.append(...) }`, which
                            // mutated a discarded copy, so a sha1 seen at more
                            // than one path kept only the first path. Append in
                            // place to the stored array.
                            lock.lock()
                            if _tracks[audioTrack.SHA1] != nil {
                                _tracks[audioTrack.SHA1]!.1.append(trackUrl)
                            } else {
                                _tracks[audioTrack.SHA1] = (audioTrack, [trackUrl])
                            }
                            lock.unlock()
                        } else {
                            Log.d("FAILED ON \(trackUrl)")
                        }
                    } catch {
                        Log.e("DOH \(url) \(error)")
                    }
                }
            }
        } catch {
            Log.e("DOH \(url) \(error)")
        }
        Log.d("done finding at: \(url.absoluteString)")
    }    
}

