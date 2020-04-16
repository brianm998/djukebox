import Vapor

let trackFinder = TrackFinder()
let audioPlayer = AudioPlayer(trackFinder: trackFinder)

// configures your application
public func configure(_ app: Application) throws {

    trackFinder.find(app: app)

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
