import Vapor

extension Data {
    static func from(file: String) throws -> Data {
        let directory = DirectoryConfiguration.detect()

        let fileURL = URL(fileURLWithPath: directory.workingDirectory)
            .appendingPathComponent(file, isDirectory: false)

        return try Data(contentsOf: fileURL)
    }
}

public class TrackFinder {

    var tracks: [AudioTrack] = []
    
    func find(at url: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for url in urls {
                if url.hasDirectoryPath {
                    find(at: url)
                } else if url.absoluteString.hasSuffix(".json") {
                    let decoder = JSONDecoder()
                    let data = try Data(contentsOf: url)
                    let audioTrack = try decoder.decode(AudioTrack.self, from: data)
                    tracks.append(audioTrack)
                }
            }
        } catch {
            print("DOH \(url)")
        }
    }
    
    func find(app: Application) {
        find(at: URL(fileURLWithPath: "/mnt/tree/mp3"))
    }
}

let trackFinder = TrackFinder()

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    //app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    trackFinder.find(app: app)

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
