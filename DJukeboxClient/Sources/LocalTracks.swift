import Foundation
import DJukeboxCommon

public protocol LocalTrackType: TrackFinderType {
    func keepLocal(sha1Hash: String, closure: @escaping (Bool) -> Void)
    func clearLocalStore()
    var downloadedTracks: [AudioTrack] { get }
    var downloadedTrackMap: [String: AudioTrack] { get }
}

// allow keeping some tracks locally for offline access 
public class LocalTracks: LocalTrackType {

    private var libDir: URL? {
        if let libraryPathURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return libraryPathURL
        }
        return nil
    }

    private var cacheDir: URL? {
        return self.urlForLibrary(appending: ["Caches", "AudioTracks"])
    }

    private var tracksJsonURL: URL? {
        return self.cacheDir?.appendingPathComponent("tracks").appendingPathExtension("json")
    }

    private func cacheDirURL(forFilename filename: String, withExtention extention: String) -> URL? {
        return self.cacheDir?.appendingPathComponent(filename).appendingPathExtension(extention)
    }

    let trackFinder: TrackFinderType
    
    public init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
        if let tracks = self.loadLocalTrackList() {
            self.downloadedTracks = tracks
            self.sanitizeDownloadedTracks()
        }
    }

    public func clearLocalStore() {
        Log.d()
        do {
            if let cacheDir = self.cacheDir {
                let list = try FileManager.default.contentsOfDirectory(at: cacheDir,
                                                                       includingPropertiesForKeys: nil)

                for url in list {
                    try FileManager.default.removeItem(at: url)
                }
            }
            self.downloadedTracks = []
            self.downloadedTrackMap = [:]
        } catch {
            Log.e("error \(error)")
        }
    }
    
    //Creating a folder 
    private func urlForLibrary(appending: [String]) -> URL? {

        if let libDir = self.libDir {

            var path: URL = libDir

            for subdir in appending {
                path = path.appendingPathComponent(subdir)
            }
            
            if !FileManager.default.fileExists(atPath: path.path) {
                do {
                    try FileManager.default.createDirectory(at: path,
                                                            withIntermediateDirectories: true,
                                                            attributes: nil)
                    
                } catch let err {
                    Log.e(err.localizedDescription)
                }
            }

            return path
        }
        return nil
    }

    fileprivate func download(url: URL,
                              toFilename filename: String,
                              andExtention extention: String,
                              closure: @escaping (Bool) -> Void)
    {
        if let libraryPathURL = self.libDir,
           let destURL = self.cacheDirURL(forFilename: filename, withExtention: extention)
        {
            if FileManager.default.fileExists(atPath: destURL.path) {
                Log.i("\(destURL.path) already exists")
                closure(true)
            } else {
                let download = URLSession.shared.downloadTask(with: url) { localURL, urlResponse, error in
                    if let localURL = localURL {
                        Log.i("moving from \(localURL) to \(destURL)")
                        do {
                            try FileManager.default.moveItem(atPath: localURL.path, toPath: destURL.path)
                            closure(true)
                        } catch {
                            Log.e("error: \(error)")
                            closure(false)
                        }
                    } else {
                        closure(false)
                    }
                }

                download.resume()
            }
        } else {
            closure(false)
        }
    }

    private func download(sha1Hash: String, closure: @escaping (AudioTrackType?) -> Void) {
        if let (track, url) = trackFinder.track(forHash: sha1Hash) {
            self.download(url: url, toFilename: track.SHA1, andExtention: "mp3") { success in
                if success {
                    closure(track)
                } else {
                    closure(nil)
                }
            }
        } else {
            closure(nil)
            Log.w("FUCK")
        }
    }

    public var downloadedTracks: [AudioTrack] = []
    public var downloadedTrackMap: [String: AudioTrack] = [:]
    
    func sanitizeDownloadedTracks() {
        var map: [AudioTrack: Bool] = [:]
        for track in self.downloadedTracks {
            map[track] = true
        }
        self.downloadedTracks = Array(map.keys)
        self.downloadedTrackMap = [:]
        for track in self.downloadedTracks {
            self.downloadedTrackMap[track.SHA1] = track
        }
    }
    
    func writeLocalTrackList() {
        let encoder = JSONEncoder()
        sanitizeDownloadedTracks()
        if let tracksJsonURL = tracksJsonURL {
            do {
                let jsonData = try encoder.encode(self.downloadedTracks)
                try jsonData.write(to: tracksJsonURL)
            } catch {
                Log.e("error: \(error)")
            }
        }
    }

    func loadLocalTrackList() -> [AudioTrack]? {
        if let tracksJsonURL = self.tracksJsonURL {
            do {
                return try JSONDecoder().decode([AudioTrack].self,
                                                from: try Data(contentsOf: tracksJsonURL))
            } catch {
                Log.i("error: \(error)")
            }
        }
        return nil
    }
    
    public func keepLocal(sha1Hash: String, closure: @escaping (Bool) -> Void) {
        self.download(sha1Hash: sha1Hash) { track in
            if let track = track as? AudioTrack,
               let tracksJsonURL = self.tracksJsonURL
            {
                Log.d("downloaded track \(track)")
                self.downloadedTracks.append(track)

                self.writeLocalTrackList()
            } else {
                Log.e("couldn't download \(track)")
            }
        }
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
        if let track = self.downloadedTrackMap[sha1Hash] {
            return track
        }
        return nil
    }

    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let track = self.downloadedTrackMap[sha1Hash],
           let url = self.cacheDirURL(forFilename: track.SHA1, withExtention: "mp3")
        {
            return (track, url)
        }
        return nil
    }
}

