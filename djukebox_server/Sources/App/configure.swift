import Vapor
import Crypto
import CryptoKit

let trackFinder: TrackFinderType = TrackFinder()
let audioPlayer: AudioPlayerType = AudioPlayer(trackFinder: trackFinder)

/*
 First look for config file in DJUKEBOX_CONFIGFILE env var
 If not found, next look DJukeboxConfig.json in working directory
 Finally, fall back to hardcoded for now
*/
let defaultConfig = Config(Password:"foobar", TrackPaths: ["/mnt/tree/mp3/Yes"])
//0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425

public struct Config: Content {
    let Password: String
    let TrackPaths: [String]
}


// configures your application
public func configure(_ app: Application) throws {

    // still need to grab list of paths from the config
    
    trackFinder.find(atFilePath: "/mnt/tree/mp3/Yes")
    //trackFinder.find(atFilePath: "/mnt/tree/mp3")
    //trackFinder.find(atFilePath: "/mnt/root/Behemoth/xfer/work/mp3")
    //trackFinder.find(atFilePath: "/mnt/root/mp3")

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
