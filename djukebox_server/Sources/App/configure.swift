import Vapor

let trackFinder: TrackFinderType = TrackFinder()
let audioPlayer: AudioPlayerType = AudioPlayer(trackFinder: trackFinder)

// configures your application
public func configure(_ app: Application) throws {

    //trackFinder.find(atFilePath: "/mnt/tree/mp3/Yes")
    trackFinder.find(atFilePath: "/mnt/tree/mp3")

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
