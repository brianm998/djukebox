import Foundation
import CSQLite
import DJukeboxCommon

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The client's local catalog of downloaded tracks, stored in SQLite. This
/// holds the full track metadata transferred from the server for each cached
/// file — and deliberately NO play history (history lives only on the server).
/// All access is serialized through one private queue. Methods log and swallow
/// errors rather than throwing, so a transient DB hiccup never breaks playback.
public final class LocalDatabase {

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "djukebox-local-database")

    public init?(path: String) {
        var ok = false
        queue.sync {
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
                Log.e("could not open local database \(path): \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            sqlite3_busy_timeout(db, 5000)
            _ = exec("PRAGMA journal_mode = WAL;", expectRow: true)
            ok = exec("""
              CREATE TABLE IF NOT EXISTS local_tracks (
                sha1 TEXT PRIMARY KEY, credit TEXT NOT NULL, artist TEXT NOT NULL, album TEXT,
                conductor TEXT, title TEXT NOT NULL, filename TEXT NOT NULL, duration TEXT,
                audio_bitrate TEXT, sample_rate TEXT, track_number TEXT, genre TEXT,
                year TEXT, original_date TEXT, downloaded_at REAL NOT NULL);
              """)
            if ok { migrateLegacyColumnNames() }
        }
        if !ok { return nil }
        Log.i("opened local database at \(path)")
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    public func allTracks() -> [AudioTrack] {
        queue.sync {
            var tracks: [AudioTrack] = []
            guard let stmt = prepare("""
              SELECT sha1, credit, artist, album, conductor, title, filename, duration,
                     audio_bitrate, sample_rate, track_number, genre, year, original_date
              FROM local_tracks;
              """) else { return tracks }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sha1 = text(stmt, 0), let credit = text(stmt, 1),
                      let artist = text(stmt, 2), let title = text(stmt, 5),
                      let filename = text(stmt, 6) else { continue }
                tracks.append(AudioTrack(
                  Credit: credit, Artist: artist, Album: text(stmt, 3),
                  Conductor: text(stmt, 4), Title: title, Filename: filename,
                  SHA1: sha1, Duration: text(stmt, 7), AudioBitrate: text(stmt, 8),
                  SampleRate: text(stmt, 9), TrackNumber: text(stmt, 10),
                  Genre: text(stmt, 11), Year: text(stmt, 12), OriginalDate: text(stmt, 13)))
            }
            return tracks
        }
    }

    /// Persists all of the server-provided metadata for a downloaded track.
    public func upsert(_ track: AudioTrack) {
        queue.sync {
            guard let stmt = prepare("""
              INSERT INTO local_tracks
                (sha1, credit, artist, album, conductor, title, filename, duration,
                 audio_bitrate, sample_rate, track_number, genre, year, original_date, downloaded_at)
              VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
              ON CONFLICT(sha1) DO UPDATE SET
                credit=excluded.credit, artist=excluded.artist, album=excluded.album,
                conductor=excluded.conductor, title=excluded.title, filename=excluded.filename,
                duration=excluded.duration, audio_bitrate=excluded.audio_bitrate,
                sample_rate=excluded.sample_rate, track_number=excluded.track_number,
                genre=excluded.genre, year=excluded.year, original_date=excluded.original_date;
              """) else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, track.SHA1)
            bind(stmt, 2, track.Credit)
            bind(stmt, 3, track.Artist)
            bind(stmt, 4, track.Album)
            bind(stmt, 5, track.Conductor)
            bind(stmt, 6, track.Title)
            bind(stmt, 7, track.Filename)
            bind(stmt, 8, track.Duration)
            bind(stmt, 9, track.AudioBitrate)
            bind(stmt, 10, track.SampleRate)
            bind(stmt, 11, track.TrackNumber)
            bind(stmt, 12, track.Genre)
            bind(stmt, 13, track.Year)
            bind(stmt, 14, track.OriginalDate)
            sqlite3_bind_double(stmt, 15, Date().timeIntervalSince1970)
            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.e("could not upsert local track: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    public func delete(sha1: String) {
        queue.sync {
            guard let stmt = prepare("DELETE FROM local_tracks WHERE sha1=?;") else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, sha1)
            _ = sqlite3_step(stmt)
        }
    }

    /// Deletes many tracks in one transaction. Used to prune rows whose audio file
    /// is no longer on disk, which can be the whole catalog — so do it in a single
    /// prepared-statement loop rather than one transaction per row.
    public func delete(shas: [String]) {
        guard !shas.isEmpty else { return }
        queue.sync {
            _ = exec("BEGIN IMMEDIATE;")
            if let stmt = prepare("DELETE FROM local_tracks WHERE sha1=?;") {
                for sha in shas {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    bind(stmt, 1, sha)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        Log.e("could not delete local track: \(String(cString: sqlite3_errmsg(db)))")
                    }
                }
                sqlite3_finalize(stmt)
            }
            _ = exec("COMMIT;")
        }
    }

    public func clear() {
        queue.sync { _ = exec("DELETE FROM local_tracks;") }
    }

    /// Renames columns left over from before the Credit/Artist rename (formerly
    /// Artist/Band). Idempotent and safe to run on every launch: a fresh
    /// `CREATE TABLE` already has the new names, so this simply won't find the
    /// old ones to rename.
    private func migrateLegacyColumnNames() {
        var columns = columnNames(ofTable: "local_tracks")
        if columns.contains("artist") && !columns.contains("credit") {
            _ = exec("ALTER TABLE local_tracks RENAME COLUMN artist TO credit;")
            columns = columnNames(ofTable: "local_tracks")
        }
        if columns.contains("band") && !columns.contains("artist") {
            _ = exec("ALTER TABLE local_tracks RENAME COLUMN band TO artist;")
        }
    }

    private func columnNames(ofTable table: String) -> Set<String> {
        // table is a fixed internal identifier, never user input.
        var names = Set<String>()
        guard let stmt = prepare("PRAGMA table_info(\(table));") else { return names }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 1) { names.insert(name) }
        }
        return names
    }

    // MARK: - low-level helpers (assume already on the serial queue)

    @discardableResult
    private func exec(_ sql: String, expectRow: Bool = false) -> Bool {
        if expectRow {
            guard let stmt = prepare(sql) else { return false }
            defer { sqlite3_finalize(stmt) }
            _ = sqlite3_step(stmt)
            return true
        }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            Log.e("sqlite exec failed: \(err.map { String(cString: $0) } ?? "?") — \(sql)")
            sqlite3_free(err)
            return false
        }
        return true
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.e("sqlite prepare failed: \(String(cString: sqlite3_errmsg(db))) — \(sql)")
            return nil
        }
        return stmt
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}
