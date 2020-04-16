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

    app.get("tracks") { req -> [AudioTrack] in
        return trackFinder.tracks.values.map { (track, _) in return track }
    }
    
    app.get("track", ":sha1") { req -> Response in
        if let hash = req.parameters.get("sha1"),
           let filepath = trackFinder.filePath(forHash: hash)
        {
            return req.fileio.streamFile(at: filepath)
        } else {
            throw Abort(.notFound)
        }
    }

    app.get("info", ":sha1") { req -> AudioTrack in
        if let hash = req.parameters.get("sha1"),
           let audioTrack = trackFinder.audioTrack(forHash: hash)
        {
            return audioTrack
        } else {
            throw Abort(.notFound)
        }
    }

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

    app.get("rand") { req -> Response in
        let random = Int.random(in: 0..<trackFinder.tracks.count)
        let hash = Array(trackFinder.tracks.keys)[random]
        audioPlayer.play(sha1Hash: hash)
        return Response(status: .ok)
    }

    app.get("stop") { req -> Response in
        audioPlayer.clearQueue()
        audioPlayer.skip()
        return Response(status: .ok)
    }

    app.get("skip") { req -> Response in
        audioPlayer.skip()
        return Response(status: .ok)
    }

    app.get("pause") { req -> Response in
        audioPlayer.pause()
        return Response(status: .ok)
    }

    app.get("resume") { req -> Response in
        audioPlayer.resume()
        return Response(status: .ok)
    }

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
