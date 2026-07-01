import Foundation
import CSQLite
import DJukeboxCommon

// SQLITE_TRANSIENT tells sqlite to copy bound text/blob immediately, instead of
// holding the (transient) pointer Swift hands it for the duration of the call.
// The macro is a function-pointer cast that does not bridge to Swift, so define
// it here.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum JukeboxDatabaseError: Error {
    case open(String)
    case prepare(String)
    case step(String)
}

/// A small synchronous SQLite store: the persistent record of the track catalog
/// and the play history. All access is funnelled through one private serial
/// queue, so it is safe to call from event-loop threads, the audio player's
/// timer thread, and `configure()` alike. We intentionally do NOT use Fluent:
/// every call site here is synchronous and completion-expecting, and bridging
/// async futures into them would either trap on an event loop or force the
/// shared player protocols to become async.
// @unchecked Sendable: the sqlite handle and all access are funnelled through the
// private serial `queue` (see the type doc above), so it is safe to share.
public final class JukeboxDatabase: @unchecked Sendable {

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "djukebox-database")

    /// Reusable model for a row that needs (re)writing during reconciliation.
    private struct ScannedFile {
        let track: AudioTrack
        let jsonPath: String
        let jsonMtime: Double
        let audioPath: String
    }

    public init(path: String) throws {
        try queue.sync {
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw JukeboxDatabaseError.open("could not open \(path): \(msg)")
            }
            sqlite3_busy_timeout(db, 5000)
            try execOnQueue("PRAGMA foreign_keys = ON;")
            // WAL improves concurrent-read durability; the pragma returns a row,
            // so run it through prepare/step rather than exec.
            try stepPragmaOnQueue("PRAGMA journal_mode = WAL;")
            try createSchemaOnQueue()
        }
        Log.i("opened database at \(path)")
    }

    deinit {
        if let db = db { sqlite3_close_v2(db) }
    }

    // MARK: - schema

    private func createSchemaOnQueue() throws {
        try execOnQueue("""
        CREATE TABLE IF NOT EXISTS tracks (
          sha1 TEXT PRIMARY KEY, artist TEXT NOT NULL, band TEXT NOT NULL, album TEXT,
          conductor TEXT, title TEXT NOT NULL, filename TEXT NOT NULL, duration TEXT,
          audio_bitrate TEXT, sample_rate TEXT, track_number TEXT, genre TEXT,
          year TEXT, original_date TEXT,
          available INTEGER NOT NULL DEFAULT 1, first_seen REAL NOT NULL, last_seen REAL NOT NULL);

        CREATE TABLE IF NOT EXISTS track_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sha1 TEXT NOT NULL REFERENCES tracks(sha1) ON DELETE CASCADE,
          json_path TEXT NOT NULL UNIQUE, json_mtime REAL NOT NULL, audio_path TEXT NOT NULL,
          available INTEGER NOT NULL DEFAULT 1, first_seen REAL NOT NULL, last_seen REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_track_files_sha1 ON track_files(sha1);

        CREATE TABLE IF NOT EXISTS play_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT, sha1 TEXT NOT NULL,
          played_at REAL NOT NULL, fully_played INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_play_history_time ON play_history(played_at);
        CREATE UNIQUE INDEX IF NOT EXISTS uq_history_event
          ON play_history(sha1, played_at, fully_played);

        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

        -- per-track / per-album / per-artist playback gain, in decibels
        -- (0 = unchanged, positive = boost). `key` is the server-assembled
        -- canonical identity for the scope (see volumeKey); the descriptive
        -- sha1/band/album columns are kept so the set can be listed back to
        -- clients. Applied by the audio player when a track starts, with
        -- precedence track > album > artist (see effectiveGainDecibels).
        CREATE TABLE IF NOT EXISTS volume_adjustment (
          scope TEXT NOT NULL CHECK (scope IN ('track','album','artist')),
          key   TEXT NOT NULL,
          sha1  TEXT, band TEXT, album TEXT,
          decibels REAL NOT NULL, updated_at REAL NOT NULL,
          PRIMARY KEY (scope, key));

        -- one row per device that has completed pairing. We store only the SHA256
        -- hash of the device's bearer token, never the token itself, so a leaked
        -- database can't be replayed against the server.
        CREATE TABLE IF NOT EXISTS paired_clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
          token_hash TEXT NOT NULL UNIQUE, created_at REAL NOT NULL, last_seen REAL NOT NULL);
        """)
    }

    // MARK: - paired clients

    /// Records a newly paired device. `tokenHash` is the SHA256 hex of the bearer
    /// token handed to the device; the raw token is never persisted.
    public func addPairedClient(name: String, tokenHash: String, at time: Double) throws {
        try queue.sync {
            try execOnQueue("""
              INSERT INTO paired_clients (name, token_hash, created_at, last_seen)
              VALUES (?,?,?,?)
              ON CONFLICT(token_hash) DO UPDATE SET name=excluded.name, last_seen=excluded.last_seen;
              """, text: [name, tokenHash], doubles: [time, time])
        }
    }

    /// The set of valid token hashes, loaded into RAM at startup so the per-request
    /// auth check never has to touch the database.
    public func loadPairedTokenHashes() throws -> Set<String> {
        try queue.sync {
            var hashes = Set<String>()
            let stmt = try prepareOnQueue("SELECT token_hash FROM paired_clients;")
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let hash = columnText(stmt, 0) { hashes.insert(hash) }
            }
            return hashes
        }
    }

    // MARK: - history: write

    public func recordPlay(of sha1: String, at time: Double) throws {
        try recordEvent(sha1: sha1, time: time, fullyPlayed: true)
    }

    public func recordSkip(of sha1: String, at time: Double) throws {
        try recordEvent(sha1: sha1, time: time, fullyPlayed: false)
    }

    private func recordEvent(sha1: String, time: Double, fullyPlayed: Bool) throws {
        try queue.sync {
            let stmt = try prepareOnQueue(
              "INSERT OR IGNORE INTO play_history (sha1, played_at, fully_played) VALUES (?,?,?);")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, sha1)
            sqlite3_bind_double(stmt, 2, time)
            sqlite3_bind_int(stmt, 3, fullyPlayed ? 1 : 0)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    // MARK: - history: read

    /// Loads the full event log into the dictionary shape the in-RAM `History`
    /// and the `/history` API use. Every event is retained.
    public func loadHistory() throws -> (plays: [String: [Double]], skips: [String: [Double]]) {
        try queue.sync {
            var plays: [String: [Double]] = [:]
            var skips: [String: [Double]] = [:]
            let stmt = try prepareOnQueue(
              "SELECT sha1, played_at, fully_played FROM play_history ORDER BY played_at;")
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sha1 = columnText(stmt, 0) else { continue }
                let time = sqlite3_column_double(stmt, 1)
                if sqlite3_column_int(stmt, 2) == 1 {
                    plays[sha1, default: []].append(time)
                } else {
                    skips[sha1, default: []].append(time)
                }
            }
            return (plays, skips)
        }
    }

    // MARK: - history: one-time legacy import

    public func isLegacyHistoryImported() -> Bool {
        return (try? metaValue(forKey: "legacy_history_imported")) == "1"
    }

    /// Imports legacy `.txt` history events and marks the import done, atomically
    /// in a single transaction so a crash can never leave a half-import that
    /// re-runs. `INSERT OR IGNORE` + the unique event index make it idempotent
    /// even if called twice. Safe to call with an empty array (just sets the
    /// marker so we never rescan the legacy files again).
    public func importLegacyHistory(_ events: [(sha1: String, time: Double, fullyPlayed: Bool)]) throws {
        try queue.sync {
            try execOnQueue("BEGIN IMMEDIATE;")
            do {
                if !events.isEmpty {
                    let stmt = try prepareOnQueue(
                      "INSERT OR IGNORE INTO play_history (sha1, played_at, fully_played) VALUES (?,?,?);")
                    defer { sqlite3_finalize(stmt) }
                    for event in events {
                        sqlite3_reset(stmt)
                        sqlite3_clear_bindings(stmt)
                        bind(stmt, 1, event.sha1)
                        sqlite3_bind_double(stmt, 2, event.time)
                        sqlite3_bind_int(stmt, 3, event.fullyPlayed ? 1 : 0)
                        guard sqlite3_step(stmt) == SQLITE_DONE else {
                            throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
                        }
                    }
                }
                try setMetaOnQueue(key: "legacy_history_imported", value: "1")
                try setMetaOnQueue(key: "legacy_history_imported_count", value: "\(events.count)")
                try execOnQueue("COMMIT;")
            } catch {
                try? execOnQueue("ROLLBACK;")
                throw error
            }
        }
        Log.i("imported \(events.count) legacy history events")
    }

    // MARK: - track catalog reconciliation

    /// Walks `musicDir`, reconciles what is on disk against the DB (incremental:
    /// JSON is only re-parsed when a sidecar is new or its modification time
    /// changed), and rebuilds `trackFinder.tracks` to reflect what is currently
    /// available on disk. Tracks/files no longer present are flagged
    /// `available = 0` rather than deleted, so history keeps resolving them.
    public func reconcile(musicDir: String, into trackFinder: TrackFinder) {
        let scanStart = Date().timeIntervalSince1970
        let musicURL = URL(fileURLWithPath: musicDir, isDirectory: true)

        // 1. existing state from the DB
        let existingFiles = (try? loadTrackFiles()) ?? [:]      // json_path -> row
        let existingMeta = (try? loadTrackMetadata()) ?? [:]    // sha1 -> AudioTrack

        // 2. walk the tree (filesystem only — no DB I/O here)
        var seen = Set<String>()                                 // json_paths found this scan
        var reactivate = [String]()                              // were available=0, now present
        var changed = [ScannedFile]()                            // need upsert
        var resultMeta: [String: AudioTrack] = [:]
        var resultPaths: [String: [URL]] = [:]

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
                at: musicURL, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]) else {
            Log.e("could not enumerate music dir \(musicDir)")
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "json" else { continue }
            let jsonPath = url.path
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
              .contentModificationDate?.timeIntervalSince1970 ?? 0

            if let row = existingFiles[jsonPath],
               abs(row.mtime - mtime) < 0.001,
               let track = existingMeta[row.sha1],
               FileManager.default.fileExists(atPath: row.audioPath)
            {
                // unchanged sidecar with a reachable audio file: reuse stored
                // metadata, skip the (expensive) JSON parse.
                seen.insert(jsonPath)
                if !row.available { reactivate.append(jsonPath) }
                resultMeta[row.sha1] = track
                resultPaths[row.sha1, default: []].append(URL(fileURLWithPath: row.audioPath))
                continue
            }

            // new or changed sidecar: parse it.
            guard let data = try? Data(contentsOf: url),
                  let track = try? JSONDecoder().decode(AudioTrack.self, from: data).sanitized
            else {
                Log.e("could not decode track json \(jsonPath)")
                continue
            }
            let audioURL = url.deletingLastPathComponent()
              .appendingPathComponent(track.Filename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                Log.d("audio file missing for \(jsonPath): \(audioURL.path)")
                continue
            }
            seen.insert(jsonPath)
            changed.append(ScannedFile(track: track, jsonPath: jsonPath,
                                       jsonMtime: mtime, audioPath: audioURL.path))
            resultMeta[track.SHA1] = track
            resultPaths[track.SHA1, default: []].append(audioURL)
        }

        // 3. persist the diff in one transaction
        queue.sync {
            do {
                try execOnQueue("BEGIN IMMEDIATE;")
                for file in changed { try upsertTrackOnQueue(file, now: scanStart) }
                for path in reactivate {
                    try execOnQueue("UPDATE track_files SET available=1 WHERE json_path=?;",
                                    text: [path])
                }
                // guard: never mass-flip availability when the scan came up empty
                // (e.g. an unmounted music volume).
                if seen.isEmpty && !existingFiles.isEmpty {
                    Log.w("reconcile found no tracks on disk but DB has \(existingFiles.count) — skipping the unavailable sweep")
                } else {
                    for (jsonPath, _) in existingFiles where !seen.contains(jsonPath) {
                        try execOnQueue("UPDATE track_files SET available=0 WHERE json_path=?;",
                                        text: [jsonPath])
                    }
                    try execOnQueue("UPDATE tracks SET available=0 WHERE sha1 NOT IN (SELECT DISTINCT sha1 FROM track_files WHERE available=1);")
                    try execOnQueue("UPDATE tracks SET available=1 WHERE sha1 IN (SELECT DISTINCT sha1 FROM track_files WHERE available=1);")
                }
                try execOnQueue("COMMIT;")
            } catch {
                Log.e("reconcile transaction failed: \(error)")
                try? execOnQueue("ROLLBACK;")
            }
        }

        // 4. rebuild the in-RAM catalog from what is available on disk now.
        // Sort paths so track(forHash:)'s urls[0] is stable across restarts.
        var tracks: [String: (AudioTrackType, [URL])] = [:]
        for (sha1, track) in resultMeta {
            let urls = (resultPaths[sha1] ?? []).sorted { $0.path < $1.path }
            tracks[sha1] = (track, urls)
        }
        trackFinder.tracks = tracks
        Log.i("reconcile: \(tracks.count) available tracks (\(changed.count) parsed, \(seen.count - changed.count) reused)")
    }

    /// Ingests a single directory at runtime (the `/discover` route): upserts
    /// what it finds and merges it into `trackFinder`, without the
    /// mark-unavailable sweep that a full reconcile performs.
    public func ingest(directory: String, into trackFinder: TrackFinder) {
        let now = Date().timeIntervalSince1970
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
                at: dirURL, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]) else {
            Log.e("could not enumerate \(directory)")
            return
        }
        var found = [ScannedFile]()
        for case let url as URL in enumerator {
            guard url.pathExtension == "json" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
              .contentModificationDate?.timeIntervalSince1970 ?? 0
            guard let data = try? Data(contentsOf: url),
                  let track = try? JSONDecoder().decode(AudioTrack.self, from: data).sanitized
            else { continue }
            let audioURL = url.deletingLastPathComponent()
              .appendingPathComponent(track.Filename, isDirectory: false)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            found.append(ScannedFile(track: track, jsonPath: url.path,
                                     jsonMtime: mtime, audioPath: audioURL.path))
        }

        queue.sync {
            do {
                try execOnQueue("BEGIN IMMEDIATE;")
                for file in found { try upsertTrackOnQueue(file, now: now) }
                try execOnQueue("COMMIT;")
            } catch {
                Log.e("ingest transaction failed: \(error)")
                try? execOnQueue("ROLLBACK;")
            }
        }

        for file in found {
            let url = URL(fileURLWithPath: file.audioPath)
            if trackFinder.tracks[file.track.SHA1] != nil {
                if !trackFinder.tracks[file.track.SHA1]!.1.contains(url) {
                    trackFinder.tracks[file.track.SHA1]!.1.append(url)
                }
            } else {
                trackFinder.tracks[file.track.SHA1] = (file.track, [url])
            }
        }
        Log.i("ingest: \(found.count) tracks from \(directory)")
    }

    // MARK: - catalog reads (on queue)

    private struct FileRow { let mtime: Double; let sha1: String; let audioPath: String; let available: Bool }

    private func loadTrackFiles() throws -> [String: FileRow] {
        try queue.sync {
            var map: [String: FileRow] = [:]
            let stmt = try prepareOnQueue(
              "SELECT json_path, json_mtime, sha1, audio_path, available FROM track_files;")
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let jsonPath = columnText(stmt, 0),
                      let sha1 = columnText(stmt, 2),
                      let audioPath = columnText(stmt, 3) else { continue }
                map[jsonPath] = FileRow(mtime: sqlite3_column_double(stmt, 1),
                                        sha1: sha1, audioPath: audioPath,
                                        available: sqlite3_column_int(stmt, 4) == 1)
            }
            return map
        }
    }

    private func loadTrackMetadata() throws -> [String: AudioTrack] {
        try queue.sync {
            var map: [String: AudioTrack] = [:]
            let stmt = try prepareOnQueue("""
              SELECT sha1, artist, band, album, conductor, title, filename, duration,
                     audio_bitrate, sample_rate, track_number, genre, year, original_date
              FROM tracks;
              """)
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sha1 = columnText(stmt, 0),
                      let artist = columnText(stmt, 1),
                      let band = columnText(stmt, 2),
                      let title = columnText(stmt, 5),
                      let filename = columnText(stmt, 6) else { continue }
                map[sha1] = AudioTrack(
                  Artist: artist, Band: band, Album: columnText(stmt, 3),
                  Conductor: columnText(stmt, 4), Title: title, Filename: filename,
                  SHA1: sha1, Duration: columnText(stmt, 7),
                  AudioBitrate: columnText(stmt, 8), SampleRate: columnText(stmt, 9),
                  TrackNumber: columnText(stmt, 10), Genre: columnText(stmt, 11),
                  Year: columnText(stmt, 12), OriginalDate: columnText(stmt, 13))
            }
            return map
        }
    }

    // MARK: - catalog writes (assume already on queue)

    private func upsertTrackOnQueue(_ file: ScannedFile, now: Double) throws {
        let t = file.track
        let trackStmt = try prepareOnQueue("""
          INSERT INTO tracks
            (sha1, artist, band, album, conductor, title, filename, duration,
             audio_bitrate, sample_rate, track_number, genre, year, original_date,
             available, first_seen, last_seen)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?)
          ON CONFLICT(sha1) DO UPDATE SET
            artist=excluded.artist, band=excluded.band, album=excluded.album,
            conductor=excluded.conductor, title=excluded.title, filename=excluded.filename,
            duration=excluded.duration, audio_bitrate=excluded.audio_bitrate,
            sample_rate=excluded.sample_rate, track_number=excluded.track_number,
            genre=excluded.genre, year=excluded.year, original_date=excluded.original_date,
            available=1, last_seen=excluded.last_seen;
          """)
        defer { sqlite3_finalize(trackStmt) }
        bind(trackStmt, 1, t.SHA1)
        bind(trackStmt, 2, t.Artist)
        bind(trackStmt, 3, t.Band)
        bind(trackStmt, 4, t.Album)
        bind(trackStmt, 5, t.Conductor)
        bind(trackStmt, 6, t.Title)
        bind(trackStmt, 7, t.Filename)
        bind(trackStmt, 8, t.Duration)
        bind(trackStmt, 9, t.AudioBitrate)
        bind(trackStmt, 10, t.SampleRate)
        bind(trackStmt, 11, t.TrackNumber)
        bind(trackStmt, 12, t.Genre)
        bind(trackStmt, 13, t.Year)
        bind(trackStmt, 14, t.OriginalDate)
        sqlite3_bind_double(trackStmt, 15, now)
        sqlite3_bind_double(trackStmt, 16, now)
        guard sqlite3_step(trackStmt) == SQLITE_DONE else {
            throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }

        let fileStmt = try prepareOnQueue("""
          INSERT INTO track_files (sha1, json_path, json_mtime, audio_path, available, first_seen, last_seen)
          VALUES (?,?,?,?,1,?,?)
          ON CONFLICT(json_path) DO UPDATE SET
            sha1=excluded.sha1, json_mtime=excluded.json_mtime,
            audio_path=excluded.audio_path, available=1, last_seen=excluded.last_seen;
          """)
        defer { sqlite3_finalize(fileStmt) }
        bind(fileStmt, 1, t.SHA1)
        bind(fileStmt, 2, file.jsonPath)
        sqlite3_bind_double(fileStmt, 3, file.jsonMtime)
        bind(fileStmt, 4, file.audioPath)
        sqlite3_bind_double(fileStmt, 5, now)
        sqlite3_bind_double(fileStmt, 6, now)
        guard sqlite3_step(fileStmt) == SQLITE_DONE else {
            throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - meta

    private func metaValue(forKey key: String) throws -> String? {
        try queue.sync {
            let stmt = try prepareOnQueue("SELECT value FROM meta WHERE key=?;")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, key)
            if sqlite3_step(stmt) == SQLITE_ROW { return columnText(stmt, 0) }
            return nil
        }
    }

    private func setMetaOnQueue(key: String, value: String) throws {
        try execOnQueue("INSERT OR REPLACE INTO meta (key, value) VALUES (?,?);",
                        text: [key, value])
    }

    public func count(ofTable table: String) -> Int {
        // table is a fixed internal identifier, never user input.
        (try? queue.sync {
            let stmt = try prepareOnQueue("SELECT COUNT(*) FROM \(table);")
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }) ?? 0
    }

    // MARK: - volume adjustments

    // Separates band from album in an album-scope key. A control character that
    // cannot occur in a tag value, so it can never collide with real metadata.
    private static let volumeKeySeparator = "\u{1f}"

    /// The canonical storage key for a scope. Throws if the fields required by
    /// the scope are missing (so a malformed request can't create a junk row).
    private func volumeKey(scope: String, sha1: String?, band: String?, album: String?) throws -> String {
        switch scope {
        case "track":
            guard let sha1 = sha1, !sha1.isEmpty else {
                throw JukeboxDatabaseError.step("track volume adjustment requires a sha1")
            }
            return sha1
        case "album":
            guard let band = band, !band.isEmpty, let album = album, !album.isEmpty else {
                throw JukeboxDatabaseError.step("album volume adjustment requires band and album")
            }
            return band + Self.volumeKeySeparator + album
        case "artist":
            guard let band = band, !band.isEmpty else {
                throw JukeboxDatabaseError.step("artist volume adjustment requires a band")
            }
            return band
        default:
            throw JukeboxDatabaseError.step("unknown volume scope \(scope)")
        }
    }

    /// Upserts a volume adjustment for a scope. `decibels` is stored as given;
    /// callers (the API) are expected to clamp to a sane range first.
    public func setVolumeAdjustment(scope: String, sha1: String?, band: String?,
                                    album: String?, decibels: Double, at time: Double) throws {
        let key = try volumeKey(scope: scope, sha1: sha1, band: band, album: album)
        try queue.sync {
            let stmt = try prepareOnQueue("""
              INSERT INTO volume_adjustment (scope, key, sha1, band, album, decibels, updated_at)
              VALUES (?,?,?,?,?,?,?)
              ON CONFLICT(scope,key) DO UPDATE SET
                sha1=excluded.sha1, band=excluded.band, album=excluded.album,
                decibels=excluded.decibels, updated_at=excluded.updated_at;
              """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, scope)
            bind(stmt, 2, key)
            bind(stmt, 3, sha1)
            bind(stmt, 4, band)
            bind(stmt, 5, album)
            sqlite3_bind_double(stmt, 6, decibels)
            sqlite3_bind_double(stmt, 7, time)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// Removes a stored adjustment (equivalent to resetting it to 0 dB).
    public func clearVolumeAdjustment(scope: String, sha1: String?,
                                      band: String?, album: String?) throws {
        let key = try volumeKey(scope: scope, sha1: sha1, band: band, album: album)
        try queue.sync {
            try execOnQueue("DELETE FROM volume_adjustment WHERE scope=? AND key=?;",
                            text: [scope, key])
        }
    }

    /// The effective gain, in decibels, that should be applied when this track
    /// plays: the most specific adjustment wins (track > album > artist). Returns
    /// 0 (unity) when nothing matches or on any error, so playback never breaks.
    public func effectiveGainDecibels(forHash sha1: String) -> Double {
        (try? queue.sync {
            // resolve the track's band/album so we can build the album/artist keys
            var band: String?
            var album: String?
            let meta = try prepareOnQueue("SELECT band, album FROM tracks WHERE sha1=?1;")
            defer { sqlite3_finalize(meta) }
            bind(meta, 1, sha1)
            if sqlite3_step(meta) == SQLITE_ROW {
                band = columnText(meta, 0)
                album = columnText(meta, 1)
            }

            let albumKey: String? = (band != nil && album != nil)
              ? band! + Self.volumeKeySeparator + album! : nil
            let artistKey = band

            // one query for all three candidate rows; a nil key binds NULL and
            // `key = NULL` never matches, so absent scopes are simply skipped
            let stmt = try prepareOnQueue("""
              SELECT scope, decibels FROM volume_adjustment
               WHERE (scope='track'  AND key=?1)
                  OR (scope='album'  AND key=?2)
                  OR (scope='artist' AND key=?3);
              """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, sha1)
            bind(stmt, 2, albumKey)
            bind(stmt, 3, artistKey)

            var byScope: [String: Double] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let scope = columnText(stmt, 0) {
                    byScope[scope] = sqlite3_column_double(stmt, 1)
                }
            }
            return byScope["track"] ?? byScope["album"] ?? byScope["artist"] ?? 0.0
        }) ?? 0.0
    }

    /// Every stored adjustment, for listing back to clients.
    public func allVolumeAdjustments()
      -> [(scope: String, sha1: String?, band: String?, album: String?, decibels: Double)] {
        (try? queue.sync {
            var ret: [(scope: String, sha1: String?, band: String?, album: String?, decibels: Double)] = []
            let stmt = try prepareOnQueue(
              "SELECT scope, sha1, band, album, decibels FROM volume_adjustment;")
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                ret.append((scope: columnText(stmt, 0) ?? "",
                            sha1: columnText(stmt, 1),
                            band: columnText(stmt, 2),
                            album: columnText(stmt, 3),
                            decibels: sqlite3_column_double(stmt, 4)))
            }
            return ret
        }) ?? []
    }

    // MARK: - master volume

    // The single global master gain, kept in the key/value `meta` table. It is a
    // REDUCTION from full volume (<= 0 dB, 0 = full) and is applied on top of the
    // per-track/album/artist adjustment (see VolumeAdjustmentProvider), so the two
    // compose additively.
    private static let masterGainMetaKey = "master_gain_db"

    /// The global master gain (dB). 0 (full volume) when unset or on any error, so
    /// playback never breaks.
    public func masterGainDecibels() -> Double {
        guard let raw = try? metaValue(forKey: Self.masterGainMetaKey),
              let db = Double(raw) else { return 0 }
        return db
    }

    /// Persist the global master gain (dB). The API clamps to a reduction-only
    /// range before calling this.
    public func setMasterGainDecibels(_ decibels: Double) throws {
        try queue.sync {
            try setMetaOnQueue(key: Self.masterGainMetaKey, value: String(decibels))
        }
    }

    // MARK: - low-level helpers (assume already on the serial queue)

    private func prepareOnQueue(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw JukeboxDatabaseError.prepare("\(String(cString: sqlite3_errmsg(db))) — \(sql)")
        }
        return stmt
    }

    /// Runs one or more statements with no result rows. Optional positional text
    /// parameters bind first (indices 1…n), then any double parameters bind after
    /// them (indices n+1…), matching the order of `?` placeholders in the SQL.
    private func execOnQueue(_ sql: String, text: [String] = [], doubles: [Double] = []) throws {
        if text.isEmpty && doubles.isEmpty {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown error"
                sqlite3_free(err)
                throw JukeboxDatabaseError.step("\(msg) — \(sql)")
            }
            return
        }
        let stmt = try prepareOnQueue(sql)
        defer { sqlite3_finalize(stmt) }
        for (i, value) in text.enumerated() { bind(stmt, Int32(i + 1), value) }
        for (i, value) in doubles.enumerated() {
            sqlite3_bind_double(stmt, Int32(text.count + i + 1), value)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw JukeboxDatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func stepPragmaOnQueue(_ sql: String) throws {
        let stmt = try prepareOnQueue(sql)
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_step(stmt)   // a pragma that returns a row must be stepped
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
