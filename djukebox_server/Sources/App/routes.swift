import Vapor

public struct AudioTrack: Content {
    let Artist: String
    let Album: String?
    let Title: String
    let Filename: String
    let SHA1: String
    let Duration: String?
    let AudioBitrate: String?
    let SampleRate: String?
    let TrackNumber: String?
    let Genre: String?
    let OriginalDate: String?
}

class AuthController {
    let config: Config
    let trackFinder: TrackFinderType
    
    init(config: Config, trackFinder: TrackFinderType) {
        self.config = config
        self.trackFinder = trackFinder
    }

    // curl -H "auth: 0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425" http://localhost:8080/rand
    func auth<T>(request req: Request, closure: () throws -> T) throws -> T {
        for header in req.headers {
            if header.name == "Authorization" {
                if SHA512.hash(data: Data(config.Password.utf8)).hexEncodedString() == header.value {
                    return try closure()
                }
            }
        }
        throw Abort(.unauthorized)
    }

    func track<T>(from req: Request,
                  closure: (AudioTrack, String) -> T) throws -> T
    {
        return try self.auth(request: req) {
            if let hash = req.parameters.get("sha1"),
               let (track, path) = trackFinder.track(forHash: hash)
            {
                return closure(track, path)
            } else {
                throw Abort(.notFound)
            }
        }
    }
}

func routes(_ app: Application) throws {

    // Json list of all known tracks
    // curl localhost:8080/tracks
    app.get("tracks") { req -> [AudioTrack] in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            return trackFinder.tracks.values.map { (track, _) in return track }
        }
    }

    // stream a track by hash
    // curl localhost:8080/stream/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stream", ":sha1") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.track(from: req) { _, filepath in
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
        return try authControl.auth(request: req) {
            let random = Int.random(in: 0..<trackFinder.tracks.count)
            let hash = Array(trackFinder.tracks.keys)[random]
            audioPlayer.play(sha1Hash: hash)
            if let audioTrack = trackFinder.audioTrack(forHash: hash) {
                return audioTrack
            } else {
                throw Abort(.notFound)
            }
        }
    }

    // Stop all playing, clearing the playing queue
    // curl localhost:8080/stop
    app.get("stop") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            audioPlayer.clearQueue()
            audioPlayer.skip()
            return Response(status: .ok)
        }
    }

    // Stop playing a particular track
    // curl localhost:8080/stop/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stop", ":sha1") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            return try authControl.track(from: req) { track, _ in
                audioPlayer.stopPlaying(sha1Hash: track.SHA1)
                return Response(status: .ok)
            }
        }
    }

    // Pause playing
    // curl localhost:8080/pause
    app.get("pause") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            audioPlayer.pause()
            return Response(status: .ok)
        }
    }

    // Resume playing
    // curl localhost:8080/resume
    app.get("resume") { req -> Response in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            audioPlayer.resume()
            return Response(status: .ok)
        }
    }

    // Json list of the current queue of playing songs
    // curl localhost:8080/resume
    app.get("queue") { req -> [AudioTrack] in
        let authControl = AuthController(config: defaultConfig, trackFinder: trackFinder)
        return try authControl.auth(request: req) {
            var tracks: [AudioTrack] = []
            if let playingTrack = audioPlayer.playingTrack {
                tracks.append(playingTrack)
            }
            for trackHash in audioPlayer.trackQueue {
                if let track = trackFinder.audioTrack(forHash: trackHash) {
                    tracks.append(track)
                }
            }
            return tracks
        }
    }
}
