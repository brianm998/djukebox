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
    app.get { req -> AudioTrack in
        let fuck = try req.fileio.collectFile(at: "/mnt/root/foo").wait()
        let foo = fuck.description
        //let fuck = try req.fileio().read(file: "/tmp/root/file").wait()
        return .init(Artist: foo,
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

    app.get("hello") { req -> String in
        return "Hello, world!"
    }
}
