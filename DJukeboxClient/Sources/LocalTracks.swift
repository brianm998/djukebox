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

    let trackFinder: TrackCatalog
    private var db: LocalDatabase?

    // Weak back-reference to the owning TrackFetcher, used ONLY to nudge its
    // @Published cache-status UI to refresh after a download/reconcile/clear
    // (fetcher.refreshTracks() / cacheDidChange()). Set by Client after both are
    // constructed (LocalTracks needs `catalog`, a property of TrackFetcher, to
    // exist first). Every use is already inside a MainActor.run / Task { @MainActor
    // in } block below, so hopping onto the fetcher's actor here is a no-op.
    public weak var fetcher: TrackFetcher?

    // SHA1s kept (downloaded) while the background reconcile scan was running;
    // main-queue only. The scan's drop list is a snapshot from init, so anything
    // in here must survive the apply step — its file was just written.
    private var keptDuringReconcile = Set<String>()
    private var reconcilePending = true

    public init(trackFinder: TrackCatalog) {
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
    //
    // The scan opens every cached file (~8 seconds for a 10k-track cache), and it
    // used to run inline in init — on the main thread, stalling the whole connect
    // flow at app startup. It now scans a snapshot of the catalog on a background
    // queue and applies the result on the main queue as a subtraction, so tracks
    // downloaded while the scan was running are kept. Until it lands, offline
    // browsing may briefly list a track whose file is gone — the same staleness
    // the catalog already had before this launch.
    private func reconcileWithDownloadedFiles() {
        let snapshot = self.downloadedTracks
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var presentCount = 0
            var drop: [String] = []
            for track in snapshot {
                guard let url = self.cacheDirURL(forFilename: track.SHA1, withExtention: "mp3") else {
                    drop.append(track.SHA1)
                    continue
                }
                let path = url.path
                if self.isLikelyAudioFile(atPath: path) {
                    presentCount += 1
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
            Log.i("local catalog reconcile: \(snapshot.count) rows, \(presentCount) valid audio, \(drop.count) missing/invalid")
            // decide AND apply the drop on the main actor, serialized with
            // keepLocal's upsert/append: a track re-downloaded mid-scan is in
            // keptDuringReconcile and must not have its fresh row deleted
            await MainActor.run {
                let dropSet = Set(drop).subtracting(self.keptDuringReconcile)
                self.keptDuringReconcile.removeAll()
                self.reconcilePending = false
                guard !dropSet.isEmpty else { return }
                self.db?.delete(shas: Array(dropSet))
                self.downloadedTracks.removeAll { dropSet.contains($0.SHA1) }
                self.sanitizeDownloadedTracks()
                if let fetcher = self.fetcher {
                    if fetcher.useLocalContentOnly {
                        // the UI is showing the local catalog (offline mode) and it
                        // just changed underneath it — republish (this also re-tints)
                        fetcher.refreshTracks()
                    } else {
                        // online: catalog is unchanged, but some rows are no longer
                        // cached — re-tint the browse lists
                        fetcher.cacheDidChange()
                    }
                }
            }
        }
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
        if let cacheDir = self.cacheDir,
           let list = try? FileManager.default.contentsOfDirectory(at: cacheDir,
                                                                   includingPropertiesForKeys: nil)
        {
            // remove the cached audio only; leave the database file (its
            // contents are emptied below) so the open connection stays valid.
            // Per-file catch: the background reconcile scan can delete a junk
            // placeholder concurrently, and one missing file must not abort
            // the clear before the database/catalog resets below.
            for url in list where url.pathExtension == "mp3" {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Log.e("error \(error)")
                }
            }
        }
        self.db?.clear()
        self.downloadedTracks = []
        self.downloadedTrackMap = [:]
        // everything just went uncached — repaint the browse lists white. This is a
        // non-isolated method (part of LocalTrackType) that may be called from the
        // main actor (TrackFetcher.clearCache()) or elsewhere, so hop explicitly
        // rather than assume the caller's context.
        Task { @MainActor [weak fetcher] in
            fetcher?.cacheDidChange()
        }
    }

    fileprivate func download(url: URL,
                              toFilename filename: String,
                              andExtention extention: String,
                              closure: @escaping @Sendable (Bool) -> Void)
    {
        Task { @MainActor in
            if let _ = LocalCache.libDir,
               let destURL = self.cacheDirURL(forFilename: filename, withExtention: extention)
            {
                if FileManager.default.fileExists(atPath: destURL.path),
                   self.isLikelyAudioFile(atPath: destURL.path)
                {
                    Log.i("\(destURL.path) already exists")
                    closure(true)
                } else {
                    // whatever is there isn't audio (e.g. an old saved error
                    // body) — clear it so it can't satisfy this fast-path again
                    // or collide with the download's moveItem below
                    try? FileManager.default.removeItem(atPath: destURL.path)
                    do {
                        let (localURL, urlResponse) = try await URLSession.shared.download(from: url)
                        // download(from:) writes the response body to localURL even for
                        // HTTP errors (401/404/5xx), so we MUST check the status — else
                        // an error page gets saved as <sha1>.mp3 and recorded as a real
                        // downloaded track (junk that can't play).
                        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                        if (200..<300).contains(status) {
                            Log.i("moving from \(localURL) to \(destURL)")
                            try FileManager.default.moveItem(atPath: localURL.path, toPath: destURL.path)
                            closure(true)
                        } else {
                            Log.w("download failed for \(filename): HTTP \(status)")
                            closure(false)
                        }
                    } catch {
                        Log.e("error: \(error)")
                        closure(false)
                    }
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
                // mutate the catalog (in memory AND the database) on the main
                // actor only, serialized with the reconcile scan's apply step —
                // which also checks keptDuringReconcile so its stale drop list
                // can't delete this fresh row
                Task { @MainActor in
                    self.db?.upsert(track)
                    if self.reconcilePending { self.keptDuringReconcile.insert(track.SHA1) }
                    self.downloadedTracks.append(track)
                    self.sanitizeDownloadedTracks()
                    // a newly cached track re-tints its artist/album/song rows
                    self.fetcher?.cacheDidChange()
                    closure(true)
                }
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
           let url = self.cacheDirURL(forFilename: track.SHA1, withExtention: "mp3"),
           // a stale row (file evicted by iOS / junk placeholder) must never
           // reach the player: a missing file makes a failed AVPlayerItem that
           // wedges the doghouse queue. The reconcile scan prunes such rows
           // asynchronously, so until it lands this sniff (a 3-byte read) is
           // what makes them fall through to the server stream URL instead.
           self.isLikelyAudioFile(atPath: url.path)
        {
            return (track, url)
        }
        return nil
    }
}
