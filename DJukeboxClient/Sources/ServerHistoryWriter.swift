import SwiftUI
import DJukeboxCommon

// this is used for writing locally played tracks to the history on the server
public class ServerHistoryWriter: HistoryWriterType {

    let server: ServerType

    public init(server: ServerType) {
        self.server = server
    }
    
    public func writePlay(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: true)
        server.post(history: history) { success, error in
            print("wrote play of \(sha1)")
        }
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: false)
        server.post(history: history) { success, error in
            print("wrote skip of \(sha1)")
        }
    }
}

