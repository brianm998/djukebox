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

func routes(_ app: Application) throws {

    // Json list of all known tracks
    // curl localhost:8080/tracks
    app.get("tracks") { req -> [AudioTrack] in
        return trackFinder.tracks.values.map { (track, _) in return track }
    }

    // stream a track by hash
    // curl localhost:8080/stream/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("stream", ":sha1") { req -> Response in
        if let hash = req.parameters.get("sha1"),
           let filepath = trackFinder.filePath(forHash: hash)
        {
            return req.fileio.streamFile(at: filepath)
        } else {
            throw Abort(.notFound)
        }
    }

    // Json info about a track by hash 
    // curl localhost:8080/info/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("info", ":sha1") { req -> AudioTrack in
        if let hash = req.parameters.get("sha1"),
           let audioTrack = trackFinder.audioTrack(forHash: hash)
        {
            return audioTrack
        } else {
            throw Abort(.notFound)
        }
    }

    // Play a track by hash.
    // curl localhost:8080/play/8ba165d9fe8f1050687dfa0f34ab42df6a29e72c
    app.get("play", ":sha1") { req -> Response in
        if let hash = req.parameters.get("sha1"),
            let _ = trackFinder.audioTrack(forHash: hash)
        {
            audioPlayer.play(sha1Hash: hash)
            return Response(status: .ok)
        } else {
            return Response(status: .notFound)
        }
    }

    // Play a randomly selected track.
    // curl localhost:8080/rand
    app.get("rand") { req -> AudioTrack in
        let random = Int.random(in: 0..<trackFinder.tracks.count)
        let hash = Array(trackFinder.tracks.keys)[random]
        audioPlayer.play(sha1Hash: hash)
        if let audioTrack = trackFinder.audioTrack(forHash: hash) {
            return audioTrack
        } else {
            throw Abort(.notFound)
        }
    }

    // Stop all playing, clearing the playing queue
    // curl localhost:8080/stop
    app.get("stop") { req -> Response in
        audioPlayer.clearQueue()
        audioPlayer.skip()
        return Response(status: .ok)
    }

    // Skip the currently playing song
    // curl localhost:8080/skip
    app.get("skip") { req -> Response in
        audioPlayer.skip()
        return Response(status: .ok)
    }

    // Pause playing
    // curl localhost:8080/pause
    app.get("pause") { req -> Response in
        audioPlayer.pause()
        return Response(status: .ok)
    }

    // Resume playing
    // curl localhost:8080/resume
    app.get("resume") { req -> Response in
        audioPlayer.resume()
        return Response(status: .ok)
    }

    // Json list of the current queue of playing songs
    // curl localhost:8080/resume
    app.get("queue") { req -> [AudioTrack] in
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
