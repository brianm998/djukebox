import Vapor
import DJukeboxCommon
import Foundation

// F32: many route handlers call straight into JukeboxDatabase (synchronous
// SQLite via a private serial DispatchQueue, see JukeboxDatabase.swift) or do
// FileManager enumeration (e.g. /discover's directory ingest). Left inline,
// that work blocks the calling NIO event-loop thread for its duration. This
// helper runs the blocking work on a background queue and bridges the result
// back with a checked continuation, so the `async` handler actually suspends
// while it runs instead of just being marked `async` for show. It deliberately
// does NOT change JukeboxDatabase itself (that's the actor-conversion, the
// "real" fix, and is out of scope here — see the F32 commit message).
func offload<T>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: try work())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public struct HistoryEntry: Content {
    public let hash: String
    public let time: Int
    public let fullyPlayed: Bool
}

public struct AudioTrack: Content, AudioTrackType {
    public let Credit: String
    public let Artist: String
    public let Album: String?
    public let Conductor: String?
    public let Title: String
    public let Filename: String
    public let SHA1: String
    public let Duration: String?
    public let AudioBitrate: String?
    public let SampleRate: String?
    public let TrackNumber: String?
    public let Genre: String?
    public let Year: String?
    public let OriginalDate: String?

    // Wire-compatible with the .json sidecars written by mp3.pl (and every
    // existing file on disk): those keys predate the Credit/Artist rename, so
    // they're pinned here rather than renamed.
    private enum CodingKeys: String, CodingKey {
        case Credit = "Artist"
        case Artist = "Band"
        case Album, Conductor, Title, Filename, SHA1, Duration
        case AudioBitrate, SampleRate, TrackNumber, Genre, Year, OriginalDate
    }

    public var timeInterval: Double? {
        if let duration = self.Duration {
            var ret: TimeInterval = 0
            // expecting 0:07:11 (approx)
            let values = duration.split(separator: " ")[0].split(separator: ":")
            if values.count == 3,
               let hours = Double(values[0]),
               let minutes = Double(values[1]),
               let seconds = Double(values[2])
            {
                ret += seconds
                ret += minutes * 60
                ret += hours * 60 * 60
            }
            return ret
        }
        return nil
    }

    private func sanitizeDuration() -> String? {
        if let duration = self.Duration,
           let index = duration.firstIndex(of: "(")
        {
            return String(duration[..<index])
        }
        return nil
    }
    
    public var sanitized: AudioTrack {
        return AudioTrack(
          Credit: self.Credit,
          Artist: self.Artist,
          Album: self.Album,
          Conductor: self.Conductor,
          Title: self.Title,
          Filename: self.Filename,
          SHA1: self.SHA1,
          Duration: self.sanitizeDuration(),
          AudioBitrate: self.AudioBitrate,
          SampleRate: self.SampleRate,
          TrackNumber: self.TrackNumber,
          Genre: self.Genre,
          Year: self.Year,
          OriginalDate: self.OriginalDate
        )
    }
}

public struct PlayingQueue: Content {
    let isPaused: Bool
    let tracks: [AudioTrack]
    let playingTrackDuration: TimeInterval?
    let playingTrackPosition: TimeInterval?
}

public struct PlayingHistory: Content {
    let plays: [String: [Double]]
    let skips: [String: [Double]]
}

// A persisted playback gain (in decibels) scoped to a single track, a whole
// album, or a whole artist. Used both as the POST body when a client sets/clears
// an adjustment and as the elements of the GET /volume listing. Only the fields
// relevant to `scope` need be set: track -> sha1, album -> artist + album,
// artist -> artist.
public struct VolumeAdjustment: Content {
    public let scope: String        // "track" | "album" | "artist"
    public let sha1: String?
    public let artist: String?
    public let album: String?
    public let decibels: Double
}

// The single global master gain (dB). A reduction from full volume (<= 0 dB;
// 0 = full), applied on top of every per-track/album/artist gain. Used as the
// GET /volume/master response and the POST /volume/master body.
public struct MasterVolume: Content {
    public let decibels: Double
}

// AudioLevels is the shared (DJukeboxCommon) wire type for the VU-meter levels;
// teach it to serialize as a Vapor response. It is already Codable, so Content's
// defaults do the rest.
extension AudioLevels: @retroactive Content {}

// A lightweight playback-position update, pushed a couple of times a second while
// playing so the client's progress bar advances between (rarer) full queue frames.
public struct PlaybackPosition: Content {
    public let position: TimeInterval?
    public let duration: TimeInterval?
}

// One frame on the /stream WebSocket. Exactly one payload field is set, picked by
// `type`, so the client can push levels, queue changes, position ticks, and
// history changes over a single connection instead of polling those endpoints.
public struct StreamFrame: Content {
    public let type: String   // "levels" | "queue" | "position" | "history"
    public var levels: AudioLevels? = nil
    public var queue: PlayingQueue? = nil
    public var position: PlaybackPosition? = nil
    public var history: PlayingHistory? = nil

    static func levels(_ l: AudioLevels) -> StreamFrame { StreamFrame(type: "levels", levels: l) }
    static func queue(_ q: PlayingQueue) -> StreamFrame { StreamFrame(type: "queue", queue: q) }
    static func position(_ p: PlaybackPosition) -> StreamFrame { StreamFrame(type: "position", position: p) }
    static func history(_ h: PlayingHistory) -> StreamFrame { StreamFrame(type: "history", history: h) }
}

func trackServingRoutes(_ app: Application) throws {

    // Json list of all known tracks
    // curl localhost:8080/tracks
    // NOTE (F32 scoping): despite being named in the audit's callout list, this
    // only copies TrackFinder's in-RAM, NSLock-guarded dictionary (see
    // TrackFinder.swift) — no JukeboxDatabase or filesystem call — so there's no
    // blocking work here worth suspending for; left as a plain sync handler.
    app.get("tracks") { req -> [AudioTrack] in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            var ret: [AudioTrack] = []
            for (track, _) in trackFinder.tracks.values {
                if let track = track as? AudioTrack {  ret.append(track) }
            }
            return ret
        }
    }

    // stream a track by hash, with auth on the path
    // curl localhost:8080/stream/0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stream", ":auth", ":sha1") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try await authControl.trackFromPath(from: req) { _, filepath in
            return try await req.fileio.asyncStreamFile(at: filepath)
        }
    }

    // Json info about a track by hash 
    // curl localhost:8080/info/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("info", ":sha1") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.track(from: req) { track, _ in
            return track
        }
    }

    // curl -H 'Authorization: 0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425' -H 'Path: /Volumes/Temp/mp3' http://127.0.0.1:8080/discover
    // F32: the worst offender — a full recursive directory walk (FileManager
    // enumerator), a JSON decode of every sidecar, and a DB transaction. Auth is
    // checked synchronously up front (cheap: loopback/token check only), then the
    // actual ingest is offloaded so the event-loop thread is free while it runs.
    app.get("discover") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }

        var path: String?
        for header in req.headers {
            if header.name == "Path" {
                path = header.value
            }
        }
        guard let path = path else { throw Abort(.badRequest) }

        Log.d("finding at path \(path)")
        try await offload {
            jukeboxDatabase.ingest(directory: path, into: trackFinder)
        }
        return Response(status: .ok)
    }
}

func historyRoutes(_ app: Application) throws {
    // json content of played tracks
    // NOTE (F32 scoping): history.all/.since only read the in-RAM, NSLock-guarded
    // `History` mirror (see History.swift) — no DB or filesystem I/O — so these
    // two GETs are left as plain synchronous handlers, same as /queue.
    app.get("history") { req -> PlayingHistory in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return history.all
        }
    }

    // json content of played tracks
    app.get("history",  ":since") { req -> PlayingHistory in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            if let sinceString = req.parameters.get("since"),
               let since = Double(sinceString)
            {
                let date = Date(timeIntervalSince1970: since)
                return history.since(time: date)
            }
            throw Abort(.notFound)
        }
    }

    // curl -H 'Authorization: foo' -H 'content-type: application/json' -d '{"hash":"foo","time":41220,"fullyPlayed":true}' http://127.0.0.1:8080/history
    // this writes to a history entry
    // F32: historyWriter.writePlay/writeSkip write through to JukeboxDatabase
    // (real, synchronous SQLite I/O via queue.sync) before updating the RAM
    // mirror, so this one genuinely blocks and is offloaded.
    app.post("history") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        let entry = try req.content.decode(HistoryEntry.self)

        try await offload {
            if entry.fullyPlayed {
                try historyWriter.writePlay(of: entry.hash,
                                            at: Date(timeIntervalSince1970: Double(entry.time)))
            } else {
                try historyWriter.writeSkip(of: entry.hash,
                                            at: Date(timeIntervalSince1970: Double(entry.time)))
            }
        }
        return Response(status: .ok)
    }

}

func playerRoutes(_ app: Application) throws {

    // Play a track by hash.
    // curl localhost:8080/play/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("play", ":sha1") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.track(from: req) { track, _ in
            audioPlayer.play(sha1Hash: track.SHA1)
            return track
        }
    }

    // Play a randomly selected track.
    // curl localhost:8080/rand
    app.get("rand") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            let random = Int.random(in: 0..<trackFinder.tracks.count)
            let hash = Array(trackFinder.tracks.keys)[random]
            audioPlayer.play(sha1Hash: hash)
            if let audioTrack = trackFinder.audioTrack(forHash: hash) as? AudioTrack {
                return audioTrack
            } else {
                throw Abort(.notFound)
            }
        }
    }

    // Play a randomly selected track by a given credit
    // curl localhost:8080/rand/Queen
    app.get("rand", ":credit") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        if let credit = req.parameters.get("credit") {
            return try authControl.headerAuth(request: req) {
                let array = trackFinder.tracks(forCredit: credit)
                let random = Int.random(in: 0..<array.count)
                let hash = Array(array.keys)[random]
                audioPlayer.play(sha1Hash: hash)
                if let audioTrack = trackFinder.audioTrack(forHash: hash) as? AudioTrack {
                    return audioTrack
                } else {
                    throw Abort(.notFound)
                }
            }
        }
        throw Abort(.notFound)
    }

    // Play a randomly selected track that hasn't been played before
    // curl localhost:8080/newrand
    app.get("newrand") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            var possibleTracks: [String] = []
            for hash in trackFinder.tracks.keys {
                if !history.hasPlay(for: hash),
                   !history.hasSkip(for: hash),
                   !isInQueue(hash)
                {
                    possibleTracks.append(hash)
                }
            }
            if(possibleTracks.count <= 0) {
                Log.w("you've listened to all of your tracks already")
                throw Abort(.notFound)
            }

            Log.d("have \(possibleTracks.count) possible new tracks")
            
            let hash = possibleTracks[Int.random(in: 0..<possibleTracks.count)]
            if let audioTrack = trackFinder.audioTrack(forHash: hash) as? AudioTrack {
                audioPlayer.play(sha1Hash: hash)
                return audioTrack
            } else {
                throw Abort(.notFound)
            }
        }
    }
    
    // Play a randomly selected track by a given credit
    // curl localhost:8080/newrand/Queen
    app.get("newrand", ":credit") { req -> AudioTrack in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        if let credit = req.parameters.get("credit") {
            return try authControl.headerAuth(request: req) {
                let array = trackFinder.tracks(forCredit: credit)

                var sha1Hash: String?
                var max = 100
                while sha1Hash == nil,
                      max > 0
                {
                    max -= 1
                    let random = Int.random(in: 0..<array.count)
                    let hash = Array(array.keys)[random]
                    if !history.hasPlay(for: hash),
                       !history.hasSkip(for: hash),
                       !isInQueue(hash)
                    {
                        sha1Hash = hash
                    }
                }
                if let sha1Hash = sha1Hash {
                    if let audioTrack = trackFinder.audioTrack(forHash: sha1Hash) as? AudioTrack {
                        audioPlayer.play(sha1Hash: sha1Hash)
                        return audioTrack
                    } else {
                        throw Abort(.notFound)
                    }
                } else {
                    throw Abort(.notFound)
                }                
            }
        }
        throw Abort(.notFound)
    }

    // clear the playing queue, leaving only the currently playing song in place
    // curl localhost:8080/stop
    app.get("stop") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.clearQueue()
            return Response(status: .ok)
        }
    }

    // XXX this endpoint can likely go away, replaced by the one below
    // Stop playing the currently playing song, referenced by sha1
    // curl localhost:8080/stop/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stop", ":sha1") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return try authControl.track(from: req) { track, _ in
                if let playingTrack = audioPlayer.playingTrack,
                   playingTrack.SHA1 == track.SHA1
                {
                    Log.d("skip")
                    audioPlayer.skip()
                    return Response(status: .ok)
                } else {
                    return Response(status: .notFound)
                }
            }
        }
    }

    // Stop playing a particular track at in index
    // curl localhost:8080/stop/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c/3
    app.get("stop", ":sha1", ":index") { req -> Response in
        Log.d("stop at index")
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return try authControl.track(from: req) { track, _ in
                if let indexStr = req.parameters.get("index"),
                   let index = Int(indexStr)
                {
                    Log.d("index \(index)")
                    if index == -1 {
                        audioPlayer.skip()
                    } else {
                        audioPlayer.stopPlaying(sha1Hash: track.SHA1, atIndex: index)
                    }
                    return Response(status: .ok)
                } else {
                    return Response(status: .badRequest)
                }
            }
        }
    }

    app.get("move", ":sha1", ":start", ":destination") { req -> PlayingQueue in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return try authControl.track(from: req) { track, _ in
                if let startParam = req.parameters.get("start"),
                   let destParam = req.parameters.get("destination"),
                   let start = Int(startParam),
                   let dest = Int(destParam)
                {
                    if audioPlayer.move(track: track, fromIndex: start, toIndex: dest) {
                        return listQueue()
                    } else {
                        throw Abort(.badRequest)
                    }
                } else {
                    throw Abort(.badRequest)
                }
            }
        }
    }
    
    // Pause playing
    // curl localhost:8080/pause
    app.get("pause") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.pause()
            return Response(status: .ok)
        }
    }

    // Resume playing
    // curl localhost:8080/resume
    app.get("resume") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.resume()
            return Response(status: .ok)
        }
    }

    // Shuffle the order of the playing queue
    // curl localhost:8080/shuffle
    app.get("shuffle") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.shuffleQueue()
            return Response(status: .ok) // XXX return the shuffled queue?
        }
    }

    // Json list of the current queue of playing songs
    // curl localhost:8080/resume
    app.get("queue") { req -> PlayingQueue in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return listQueue()
        }
    }

    // Current per-channel output loudness (0...1) of the server's own playback,
    // for the clients' vacuum-tube VU meter. Cheap and stateless; a client polls
    // it a few times a second while the server is the one playing. On a Linux
    // server (ffplay subprocess) this reports `available: false` and the meter
    // rests, since the audio never passes through this process to be measured.
    // curl localhost:8080/levels
    app.get("levels") { req -> AudioLevels in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return audioPlayer.outputLevels
        }
    }

    // Single push channel replacing the /levels, /queue and /history polling: a
    // client opens this WebSocket and the server pushes VU levels (~20 Hz while
    // playing), the playing queue (on change) with position ticks (~2 Hz while
    // playing), and the play history (on change). Nothing is sent while idle, so
    // an idle connection is silent. See StreamSession. Auth mirrors the REST
    // routes (loopback or token).
    app.webSocket("stream") { req, ws in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else {
            _ = ws.close(code: .policyViolation)
            return
        }
        let session = StreamSession(ws: ws)
        session.start()
        // retains `session` until the socket closes, then tears down its timer
        ws.onClose.whenComplete { _ in session.stop() }
    }

    // Fill the queue with random tracks up to (but not exceeding) the given Unix timestamp.
    // curl localhost:8080/playuntil/1750000000
    // NOTE (F32 scoping): despite being named in the audit's callout list, this
    // handler only touches in-RAM audioPlayer/trackFinder state (no JukeboxDatabase
    // or filesystem calls) — same category as /queue, /move, /shuffle — so there is
    // no blocking work here worth suspending for; left as a plain sync handler.
    app.get("playuntil", ":timestamp") { req -> PlayingQueue in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            guard let timestampStr = req.parameters.get("timestamp"),
                  let targetTimestamp = Double(timestampStr)
            else { throw Abort(.badRequest) }

            let targetDate = Date(timeIntervalSince1970: targetTimestamp)
            let now = Date()
            guard targetDate > now else { return listQueue() }

            let secondsUntilTarget = targetDate.timeIntervalSince(now)

            var queuedDuration: TimeInterval = 0
            if let playingTrack = audioPlayer.playingTrack {
                let trackDuration = audioPlayer.playingTrackDuration ?? playingTrack.timeInterval ?? 0
                let position = audioPlayer.playingTrackPosition ?? 0
                queuedDuration += max(0, trackDuration - position)
            }
            for hash in audioPlayer.trackQueue {
                if let track = trackFinder.audioTrack(forHash: hash),
                   let duration = track.timeInterval
                {
                    queuedDuration += duration
                }
            }

            var timeToFill = secondsUntilTarget - queuedDuration
            guard timeToFill > 0 else { return listQueue() }

            let candidates = Array(trackFinder.tracks.keys).shuffled()
            for hash in candidates {
                guard timeToFill > 0 else { break }
                if !isInQueue(hash),
                   let track = trackFinder.audioTrack(forHash: hash),
                   let duration = track.timeInterval,
                   duration > 0,
                   duration <= timeToFill
                {
                    audioPlayer.play(sha1Hash: hash)
                    timeToFill -= duration
                }
            }

            return listQueue()
        }
    }

    @Sendable func isInQueue(_ hash: String) -> Bool {
        if let playingTrack = audioPlayer.playingTrack,
           playingTrack.SHA1 == hash
        {
            return true
        }

        for queueHash in audioPlayer.trackQueue {
            if queueHash == hash { return true }
        }

        return false
    }
}

// Snapshot of the server's current playing queue. File-scope so the /queue route
// and the /stream push (StreamSession) build it the same way.
@Sendable func listQueue() -> PlayingQueue {
    var tracks: [AudioTrack] = []
    if let playingTrack = audioPlayer.playingTrack as? AudioTrack {
        tracks.append(playingTrack)
    }
    for trackHash in audioPlayer.trackQueue {
        if let track = trackFinder.audioTrack(forHash: trackHash) as? AudioTrack {
            tracks.append(track)
        }
    }
    return PlayingQueue(isPaused: audioPlayer.isPaused, // XXX centralize paused state
                        tracks: tracks,
                        playingTrackDuration: audioPlayer.playingTrackDuration,
                        playingTrackPosition: audioPlayer.playingTrackPosition)
}

// server-side clamp so a client can't request an extreme (clipping / silencing)
// gain. Boost is the point of the feature; a little cut is allowed too.
private let volumeDecibelLimit = 24.0

// the master knob only attenuates: 0 dB = full volume, down to this many dB of cut.
private let masterReductionLimit = 30.0

func volumeRoutes(_ app: Application) throws {

    // list every stored volume adjustment
    // curl localhost:8080/volume
    // F32: jukeboxDatabase.allVolumeAdjustments() is a real synchronous SQLite
    // read (via queue.sync); offloaded so the event loop isn't blocked for it.
    app.get("volume") { req async throws -> [VolumeAdjustment] in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        return try await offload {
            jukeboxDatabase.allVolumeAdjustments().map {
                VolumeAdjustment(scope: $0.scope, sha1: $0.sha1,
                                 artist: $0.artist, album: $0.album, decibels: $0.decibels)
            }
        }
    }

    // the effective (saved) gain for a SPECIFIC track, so a client can pre-fill
    // its volume control. Resolves precedence track > album > artist; 0 dB if none.
    // Keyed by the track's own sha1 (not "what's playing") so it is correct even
    // when the client plays locally or the sheet is about a queued/other track.
    // curl localhost:8080/volume/for/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    // F32: effectiveGainDecibels does a real synchronous SQLite read; offloaded.
    app.get("volume", "for", ":sha1") { req async throws -> VolumeAdjustment in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        guard let sha1 = req.parameters.get("sha1") else { throw Abort(.badRequest) }
        let db = try await offload { jukeboxDatabase.effectiveGainDecibels(forHash: sha1) }
        return VolumeAdjustment(scope: "track", sha1: sha1, artist: nil, album: nil, decibels: db)
    }

    // live audition: set the currently-playing track's gain right now, WITHOUT
    // persisting. Used while the user drags the volume (or master) slider so they
    // can hear it. The client sends the COMBINED per-track + master level, which can
    // dip well below the ±24 dB per-scope limit, so the low end is only bounded by
    // the audio pipeline's -96 dB floor; boost is still capped.
    // curl localhost:8080/volume/live/6.5
    // NOTE (F32 scoping): only touches in-RAM audioPlayer state, no DB — left sync.
    app.get("volume", "live", ":decibels") { req -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            guard let raw = req.parameters.get("decibels"), let db = Double(raw) else {
                throw Abort(.badRequest)
            }
            audioPlayer.setLivePlaybackGain(decibels: max(-96, min(volumeDecibelLimit, db)))
            return Response(status: .ok)
        }
    }

    // set (upsert) one adjustment
    // curl -H 'content-type: application/json' -d '{"scope":"track","sha1":"…","decibels":6}' localhost:8080/volume
    // F32: setVolumeAdjustment is a real synchronous SQLite write; offloaded.
    app.post("volume") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        let adj = try req.content.decode(VolumeAdjustment.self)
        let clamped = max(-volumeDecibelLimit, min(volumeDecibelLimit, adj.decibels))
        try await offload {
            try jukeboxDatabase.setVolumeAdjustment(scope: adj.scope, sha1: adj.sha1,
                                                    artist: adj.artist, album: adj.album,
                                                    decibels: clamped,
                                                    at: Date().timeIntervalSince1970)
        }
        return Response(status: .ok)
    }

    // clear one adjustment (reset to 0 dB). Same body shape; decibels ignored.
    // curl -H 'content-type: application/json' -d '{"scope":"track","sha1":"…","decibels":0}' localhost:8080/volume/clear
    // F32: clearVolumeAdjustment is a real synchronous SQLite write; offloaded.
    app.post("volume", "clear") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        let adj = try req.content.decode(VolumeAdjustment.self)
        try await offload {
            try jukeboxDatabase.clearVolumeAdjustment(scope: adj.scope, sha1: adj.sha1,
                                                      artist: adj.artist, album: adj.album)
        }
        return Response(status: .ok)
    }

    // the global master gain (dB, <= 0). Applied on top of every per-track gain, so
    // clients read it to fill the top-level master control. 0 dB = full volume.
    // curl localhost:8080/volume/master
    // F32: masterGainDecibels reads through the database's `meta` table
    // synchronously; offloaded.
    app.get("volume", "master") { req async throws -> MasterVolume in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        let db = try await offload { jukeboxDatabase.masterGainDecibels() }
        return MasterVolume(decibels: db)
    }

    // set the global master gain. Clamped reduction-only: -30 dB … 0 dB (full), so
    // the master can only cut from full volume, never boost.
    // curl -H 'content-type: application/json' -d '{"decibels":-6}' localhost:8080/volume/master
    // F32: setMasterGainDecibels is a real synchronous SQLite write; offloaded.
    app.post("volume", "master") { req async throws -> Response in
        let authControl = AuthController(pairing: pairingService, trackFinder: trackFinder)
        guard authControl.authorizes(req) else { throw Abort(.unauthorized) }
        let mv = try req.content.decode(MasterVolume.self)
        let clamped = max(-masterReductionLimit, min(0, mv.decibels))
        try await offload {
            try jukeboxDatabase.setMasterGainDecibels(clamped)
        }
        return Response(status: .ok)
    }
}

func routes(_ app: Application) throws {

    try trackServingRoutes(app)
    try historyRoutes(app)
    try playerRoutes(app)
    try volumeRoutes(app)
    try pairingRoutes(app)
}

