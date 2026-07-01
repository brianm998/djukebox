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
        self.reconcileWithDownloadedFiles()
    }

    // The SQLite catalog is only an index of what we've downloaded; the audio files
    // are the source of truth. They drift apart in two ways: iOS reclaims
    // Library/Caches under storage pressure (deleting the .mp3 while the row
    // survives), and a past download bug saved HTTP error bodies as <sha1>.mp3 (a
    // "present" file that isn't audio). Either way offline mode listed tracks that
    // don't really exist. Keep only rows whose file is genuinely an audio file,
    // prune the rest, and delete any bogus placeholder so the catalog self-heals.
    private func reconcileWithDownloadedFiles() {
        var present: [AudioTrack] = []
        var drop: [String] = []
        for track in self.downloadedTracks {
            guard let url = self.cacheDirURL(forFilename: track.SHA1, withExtention: "mp3") else {
                drop.append(track.SHA1)
                continue
            }
            let path = url.path
            if self.isLikelyAudioFile(atPath: path) {
                present.append(track)
            } else {
                drop.append(track.SHA1)
                // Remove a small non-audio placeholder (e.g. a saved error body) so it
                // can't waste space or resurrect the row via download()'s "already
                // exists" fast-path. Size-guarded so a genuine track is never deleted.
                if FileManager.default.fileExists(atPath: path),
                   let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber,
                   size.intValue < 65536 {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
        Log.i("local catalog reconcile: \(self.downloadedTracks.count) rows, \(present.count) valid audio, \(drop.count) missing/invalid")
        guard !drop.isEmpty else { return }
        self.db?.delete(shas: drop)
        self.downloadedTracks = present
        self.sanitizeDownloadedTracks()
    }

    // Cheaply decide whether a cached file is really audio by sniffing its first
    // bytes (an mp3 starts with an "ID3" tag or an MPEG frame sync). This rejects
    // saved HTTP error bodies (JSON/HTML/empty) without reading the whole file.
    private func isLikelyAudioFile(atPath path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 3)
        guard head.count == 3 else { return false }
        let b = [UInt8](head)
        if b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 { return true }   // "ID3"
        if b[0] == 0xFF, (b[1] & 0xE0) == 0xE0 { return true }         // MPEG frame sync
        return false
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
                        // downloadTask writes the response body to localURL even for
                        // HTTP errors (401/404/5xx), so we MUST check the status — else
                        // an error page gets saved as <sha1>.mp3 and recorded as a real
                        // downloaded track (junk that can't play).
                        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                        if let localURL = localURL, error == nil, (200..<300).contains(status) {
                            Log.i("moving from \(localURL) to \(destURL)")
                            do {
                                try FileManager.default.moveItem(atPath: localURL.path, toPath: destURL.path)
                                closure(true)
                            } catch {
                                Log.e("error: \(error)")
                                closure(false)
                            }
                        } else {
                            Log.w("download failed for \(filename): HTTP \(status), error \(String(describing: error))")
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
