import Vapor
import Crypto
import CryptoKit
import DJukeboxCommon

let trackFinder/*: TrackFinderType*/ = TrackFinder()

let history = History()

// The persistent store of record for the track catalog and play history. Opened
// eagerly here (file-scope `let`s initialise lazily on first access, and the
// data dependency below guarantees the database is ready before any writer
// touches it). `try!` = fail fast at launch if the database can't be opened.
let jukeboxDatabase = try! JukeboxDatabase(path: databasePath)

let historyWriter = HistoryWriter(database: jukeboxDatabase, history: history)

// advertises this server on the local network via mDNS / Bonjour
var serviceAdvertiser: ServiceAdvertiser?

// Owns the device-pairing state: the set of tokens belonging to already-paired
// devices (seeded from the database) plus the short-lived table of pending
// pairing requests. Loopback clients are trusted without a token; everyone on the
// WiFi must pair. Lazily initialised, so it is built after `jukeboxDatabase`.
let pairingService = PairingService(database: jukeboxDatabase,
                                    tokenHashes: (try? jukeboxDatabase.loadPairedTokenHashes()) ?? [])

#if os(Linux)
let audioPlayer: AudioPlayerType = LinuxAudioPlayer(trackFinder: trackFinder,
                                                    historyWriter: historyWriter)
#else
let audioPlayer: AudioPlayerType = MacAudioPlayer(trackFinder: trackFinder,
                                                  historyWriter: historyWriter)
#endif

// where the music (and its *.json sidecars) live
let musicDir = ProcessInfo.processInfo.environment["DJUKEBOX_MUSIC_DIR"] ?? "/qp/mp3/"

// legacy play-history text files, imported into the database once on first run
let historyDir = ProcessInfo.processInfo.environment["DJUKEBOX_HISTORY_DIR"] ?? "/qp/mp3/playing_history"

// the sqlite database file. Defaults to db.sqlite in the working directory
// (already in .gitignore); override with DJUKEBOX_DB_PATH.
let databasePath = ProcessInfo.processInfo.environment["DJUKEBOX_DB_PATH"] ?? "db.sqlite"

// Writes play/skip events through to the database (the store of record) first,
// then updates the in-RAM history mirror. A failed database write propagates so
// callers (POST /history, the audio player) can report it; the in-RAM mirror is
// only touched on success and is rebuilt from the database on the next restart.
public class HistoryWriter: HistoryWriterType {
    let database: JukeboxDatabase
    let history: History

    init(database: JukeboxDatabase, history: History) {
        self.database = database
        self.history = history
    }

    public func writePlay(of sha1: String, at date: Date) throws {
        try database.recordPlay(of: sha1, at: date.timeIntervalSince1970)
        history.recordPlay(of: sha1, at: date)
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        try database.recordSkip(of: sha1, at: date.timeIntervalSince1970)
        history.recordSkip(of: sha1, at: date)
    }
}

// configures your application
public func configure(_ app: Application) throws {
    Log.handlers =
      [
        .console: ConsoleLogHandler(at: .debug),
      ]

    Log.i("server starting")

    // reconcile the on-disk catalog against the database (incremental: only
    // re-parses *.json sidecars that are new or whose modification time changed)
    // and rebuild the in-RAM catalog from what is currently available on disk.
    jukeboxDatabase.reconcile(musicDir: musicDir, into: trackFinder)
    Log.d("catalog: \(trackFinder.tracks.count) available tracks (db tracks=\(jukeboxDatabase.count(ofTable: "tracks")))")

    // one-time import of the legacy .txt history into the database
    if !jukeboxDatabase.isLegacyHistoryImported() {
        do {
            try jukeboxDatabase.importLegacyHistory(History.legacyEvents(inDirectory: historyDir))
        } catch {
            Log.e("legacy history import failed: \(error)")
        }
    }

    // load the persisted play history into the in-RAM mirror
    do {
        let loaded = try jukeboxDatabase.loadHistory()
        history.load(plays: loaded.plays, skips: loaded.skips)
        Log.d("history: \(jukeboxDatabase.count(ofTable: "play_history")) events across \(history.plays.count) tracks")
    } catch {
        Log.e("could not load history from database: \(error)")
    }

    // advertise this server on the local network so clients can find it via mDNS
    // instead of a hardcoded IP address.
    let advertiser = ServiceAdvertiser(name: "DJukebox",
                                       type: "_djukebox._tcp.",
                                       port: app.http.server.configuration.port)
    advertiser.start()
    serviceAdvertiser = advertiser

    // build pairing state (token set loaded from the database)
    Log.d("pairing: \(jukeboxDatabase.count(ofTable: "paired_clients")) paired device(s); loopback is trusted without pairing")
    _ = pairingService

    // register routes
    try routes(app)
}
