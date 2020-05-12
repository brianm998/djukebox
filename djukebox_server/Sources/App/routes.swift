import Vapor
import DJukeboxCommon

public struct HistoryEntry: Content {
    public let hash: String
    public let time: Int
    public let fullyPlayed: Bool
}

public struct AudioTrack: Content, AudioTrackType {
    public let Artist: String
    public let Band: String
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

func trackServingRoutes(_ app: Application) throws {

    // Json list of all known tracks
    // curl localhost:8080/tracks
    app.get("tracks") { req -> [AudioTrack] in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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
    app.get("stream", ":auth", ":sha1") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.trackFromPath(from: req) { _, filepath in
            return req.fileio.streamFile(at: filepath)
        }
    }

    // Json info about a track by hash 
    // curl localhost:8080/info/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("info", ":sha1") { req -> AudioTrack in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.track(from: req) { track, _ in
            return track
        }
    }

    // curl -H 'Authorization: 0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425' -H 'Path: /Volumes/Temp/mp3' http://127.0.0.1:8080/discover
    app.get("discover") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            var path: String?
            for header in req.headers {
                if header.name == "Path" {
                    path = header.value
                }
            }
            if let path = path {
                Log.d("finding at path \(path)")
                trackFinder.find(atFilePath: path)
                return Response(status: .ok)
            } else {
                throw Abort(.badRequest)
            }
        }
    }
}

func historyRoutes(_ app: Application) throws {
    // json content of played tracks
    app.get("history") { req -> PlayingHistory in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return history.all
        }
    }

    // json content of played tracks
    app.get("history",  ":since") { req -> PlayingHistory in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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
    app.post("history") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            let entry = try req.content.decode(HistoryEntry.self)

            if entry.fullyPlayed {
                try historyWriter.writePlay(of: entry.hash,
                                            at: Date(timeIntervalSince1970: Double(entry.time)))
            } else {
                try historyWriter.writeSkip(of: entry.hash,
                                            at: Date(timeIntervalSince1970: Double(entry.time)))
            }
            return Response(status: .ok)
        }
    }
    
}

func playerRoutes(_ app: Application) throws {

    // Play a track by hash.
    // curl localhost:8080/play/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("play", ":sha1") { req -> AudioTrack in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.track(from: req) { track, _ in
            audioPlayer.play(sha1Hash: track.SHA1)
            return track
        }
    }

    // Play a randomly selected track.
    // curl localhost:8080/rand
    app.get("rand") { req -> AudioTrack in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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

    // Play a randomly selected track by a given artist
    // curl localhost:8080/rand/Queen
    app.get("rand", ":artist") { req -> AudioTrack in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        if let artist = req.parameters.get("artist") {
            return try authControl.headerAuth(request: req) {
                let array = trackFinder.tracks(forArtist: artist)
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
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            var sha1Hash: String?
            var max = 100
            while sha1Hash == nil,
                  max > 0
            {
                max -= 1
                let random = Int.random(in: 0..<trackFinder.tracks.count)
                let hash = Array(trackFinder.tracks.keys)[random]
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

    // Play a randomly selected track by a given artist
    // curl localhost:8080/newrand/Queen
    app.get("newrand", ":artist") { req -> AudioTrack in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        if let artist = req.parameters.get("artist") {
            return try authControl.headerAuth(request: req) {
                let array = trackFinder.tracks(forArtist: artist)

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

    // Stop all playing, clearing the playing queue
    // curl localhost:8080/stop
    app.get("stop") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.clearQueue()
            audioPlayer.skip()
            return Response(status: .ok)
        }
    }

    // XXX this endpoint can likely go away, replaced by the one below
    // Stop playing the currently playing song, referenced by sha1
    // curl localhost:8080/stop/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stop", ":sha1") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
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
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.pause()
            return Response(status: .ok)
        }
    }

    // Resume playing
    // curl localhost:8080/resume
    app.get("resume") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            audioPlayer.resume()
            return Response(status: .ok)
        }
    }

    // Json list of the current queue of playing songs
    // curl localhost:8080/resume
    app.get("queue") { req -> PlayingQueue in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.headerAuth(request: req) {
            return listQueue()
        }
    }

    func isInQueue(_ hash: String) -> Bool {
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
    
    func listQueue() -> PlayingQueue {
        var tracks: [AudioTrack] = []
        if let playingTrack = audioPlayer.playingTrack as? AudioTrack {
            tracks.append(playingTrack)
        }
        for trackHash in audioPlayer.trackQueue {
            if let track = trackFinder.audioTrack(forHash: trackHash) as? AudioTrack {
                tracks.append(track)
            }
        }
        return PlayingQueue(isPaused: !audioPlayer.isPlaying, // XXX centralize paused state
                            tracks: tracks,
                            playingTrackDuration: audioPlayer.playingTrackDuration,
                            playingTrackPosition: audioPlayer.playingTrackPosition)
    }
}

func routes(_ app: Application) throws {
    
    try trackServingRoutes(app)
    try historyRoutes(app)
    try playerRoutes(app)
}

