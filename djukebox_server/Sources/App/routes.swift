import Vapor

struct AudioTrack: Content, Hashable {
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
    app.get { req -> AudioTrack in
        return .init(Artist: "foo",
                     Album: "me",
                     Title: "me",
                     Filename: "me",
                     SHA1: "me",
                     Duration: "me",
                     AudioBitrate: "me",
                     SampleRate: "me",
                     TrackNumber: "me",
                     Genre: "me",
                     OriginalDate: "never")
    
    }

    app.get("tracks") { req -> [AudioTrack] in
        return Array(trackFinder.tracks.keys)
    }
    
    /*
     XXX get it working so that it can serve a track by SHA1 hash
     */
     
    app.get("track") { req -> Response in
        let filename = "/mnt/root/mp3/Yes/Relayer/Yes=Relayer=01=The_Gates_of_Delirium.mp3"
        return req.fileio.streamFile(at: filename)
    }
}
