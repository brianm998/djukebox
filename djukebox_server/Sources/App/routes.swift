import Vapor

struct AudioTrack: Content {
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
}
