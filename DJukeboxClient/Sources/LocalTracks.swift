import Foundation
import DJukeboxCommon

public protocol LocalTrackType: TrackFinderType {
    func keepLocal(sha1Hash: String, closure: @escaping @Sendable (Bool) -> Void)
    func clearLocalStore()
    var downloadedTracks: [AudioTrack] { get }
    var downloadedTrackMap: [String: AudioTrack] { get }
}

// allow keeping some tracks locally for offline access.
// The downloaded audio files live in Caches/AudioTracks/<sha1>.mp3 and the full
// track metadata for each is persisted in a local SQLite database
// (local_tracks.sqlite3) alongside them. The metadata is exactly what the server
// transferred for the file; no play history is stored locally.
// @unchecked Sendable: implements LocalTrackType (refining the non-isolated
// TrackFinderType), so it can't be @MainActor. Downloads and the metadata store are
// serialized through the download completion path. See the client concurrency note
// in AsyncAudioPlayer.
public class LocalTracks: LocalCache, LocalTrackType, @unchecked Sendable {

    private var cacheDir: URL? {
        return LocalCache.urlForLibrary(appending: ["Caches", "AudioTracks"])
    }

    // legacy metadata manifest, migrated into the database once on first launch
    private var tracksJsonURL: URL? {
        return self.cacheDir?.appendingPathComponent("tracks").appendingPathExtension("json")
    }

    private var databaseURL: URL? {
        return self.cacheDir?.appendingPathComponent("local_tracks").appendingPathExtension("sqlite3")
    }

    private func cacheDirURL(forFilename filename: String, withExtention extention: String) -> URL? {
        return self.cacheDir?.appendingPathComponent(filename).appendingPathExtension(extention)
    }

    let trackFinder: TrackFinderType
    private var db: LocalDatabase?

    public init(trackFinder: TrackFinderType) {
        self.trackFinder = trackFinder
        super.init()
        if let databaseURL = self.databaseURL {
            self.db = LocalDatabase(path: databaseURL.path)
        }
        self.downloadedTracks = self.db?.allTracks() ?? []
        self.sanitizeDownloadedTracks()
        self.migrateLegacyTracksJsonIfNeeded()
    }

    public func clearLocalStore() {
        do {
            if let cacheDir = self.cacheDir {
                let list = try FileManager.default.contentsOfDirectory(at: cacheDir,
                                                                       includingPropertiesForKeys: nil)
                // remove the cached audio only; leave the database file (its
                // contents are emptied below) so the open connection stays valid.
                for url in list where url.pathExtension == "mp3" {
                    try FileManager.default.removeItem(at: url)
                }
            }
            self.db?.clear()
            self.downloadedTracks = []
            self.downloadedTrackMap = [:]
        } catch {
            Log.e("error \(error)")
        }
    }

    fileprivate func download(url: URL,
                              toFilename filename: String,
                              andExtention extention: String,
                              closure: @escaping @Sendable (Bool) -> Void)
    {
        DispatchQueue.main.async {
            if let _ = LocalCache.libDir,
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
    }

    private func download(sha1Hash: String, closure: @escaping @Sendable (AudioTrackType?) -> Void) {
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
            Log.w("no track for hash \(sha1Hash)")
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

    // One-time import of the old tracks.json manifest into the database. Runs
    // only when the database has no tracks yet; the manifest file is left in
    // place (non-destructive).
    private func migrateLegacyTracksJsonIfNeeded() {
        guard self.downloadedTracks.isEmpty else { return }
        guard let legacy = self.loadLegacyTrackList(), !legacy.isEmpty else { return }
        Log.i("migrating \(legacy.count) tracks from tracks.json into the local database")
        for track in legacy { self.db?.upsert(track) }
        self.downloadedTracks = legacy
        self.sanitizeDownloadedTracks()
    }

    private func loadLegacyTrackList() -> [AudioTrack]? {
        if let tracksJsonURL = self.tracksJsonURL {
            do {
                return try JSONDecoder().decode([AudioTrack].self,
                                                from: try Data(contentsOf: tracksJsonURL))
            } catch {
                Log.i("no legacy tracks.json to migrate: \(error)")
            }
        }
        return nil
    }

    public func keepLocal(sha1Hash: String, closure: @escaping @Sendable (Bool) -> Void) {
        self.download(sha1Hash: sha1Hash) { track in
            if let track = track as? AudioTrack {
                self.downloadedTracks.append(track)
                self.sanitizeDownloadedTracks()
                self.db?.upsert(track)
                closure(true)
            } else {
                Log.e("couldn't download \(String(describing: track))")
                closure(false)
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
