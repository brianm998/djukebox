import Vapor
import Crypto
import CryptoKit
import DJukeboxCommon

let trackFinder/*: TrackFinderType*/ = TrackFinder()

let historyDir = "/mnt/root/mp3/playing_history"

let historyWriter = HistoryWriter(dirname: historyDir)

let history = History()

#if os(Linux)
let audioPlayer: AudioPlayerType = LinuxAudioPlayer(trackFinder: trackFinder,
                                                    historyWriter: historyWriter)
#else
let audioPlayer: AudioPlayerType = MacAudioPlayer(trackFinder: trackFinder,
                                                  historyWriter: historyWriter)
#endif

/*
 First look for config file in DJUKEBOX_CONFIGFILE env var
 If not found, next look DJukeboxConfig.json in working directory
 Finally, fall back to hardcoded for now
*/
let defaultConfig = Config(Password:"foobar",
                           TrackPaths: ["/mnt/tree/mp3"])
//0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425

public struct Config: Content {
    let Password: String
    let TrackPaths: [String]
}

enum FileWriteError: Error {
    case directoryDoesntExist
    case convertToDataIssue
}

class FileWriter {

    var filename: String

    init(_ filename: String) {
        self.filename = filename
    }
    
    func write(_ text: String) throws {
        let encoding = String.Encoding.utf8

        guard let data = text.data(using: encoding) else {
            throw FileWriteError.convertToDataIssue
        }

        let fileURL = URL(fileURLWithPath: "\(filename)")

        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } else {
            try text.write(to: fileURL, atomically: false, encoding: encoding)
        }
    }
}
public class HistoryWriter: HistoryWriterType {
    let dirname: String
    let dateFormatter = DateFormatter()
    
    init(dirname: String) {
        self.dirname = dirname
        dateFormatter.dateFormat = "MM_dd_yyyy"
    }

    public func writePlay(of sha1: String, at date: Date) throws {
        let filename = "history_\(dateFormatter.string(from: Date())).txt"
        let writer = FileWriter("\(dirname)/\(filename)")
        try writer.write("\(sha1),\(date.timeIntervalSince1970),1\n")
        history.recordPlay(of: sha1, at: date)
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        let filename = "history_\(dateFormatter.string(from: Date())).txt"
        let writer = FileWriter("\(dirname)/\(filename)")
        try writer.write("\(sha1),\(date.timeIntervalSince1970),0\n")
        history.recordSkip(of: sha1, at: date)
    }
}

// configures your application
public func configure(_ app: Application) throws {

    // still need to grab list of paths from the config
    
    trackFinder.find(atFilePath: "/Volumes/Temp/mp3/")
    //trackFinder.find(atFilePath: "/mnt/tree/mp3")
    //trackFinder.find(atFilePath: "/mnt/root/mp3/Yes")
    //trackFinder.find(atFilePath: "/mnt/tree/mp3/Das_Ich")

    //trackFinder.find(atFilePath: "/mnt/root/Behemoth/xfer/work/mp3")
    //trackFinder.find(atFilePath: "/mnt/root/mp3")

    history.find(atFilePath: historyDir)

    print("test finder has found \(trackFinder.tracks.count) tracks")
    
    // register routes
    try routes(app)
}
