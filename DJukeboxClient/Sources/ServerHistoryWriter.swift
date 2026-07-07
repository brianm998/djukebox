import SwiftUI
import DJukeboxCommon

// this is used for writing locally played tracks to the history on the server
//
// @unchecked Sendable: implements the non-isolated HistoryWriterType and is called
// from the audio player's background callbacks; it only holds an immutable server
// reference and posts to it. See the client concurrency note in AsyncAudioPlayer.
public class ServerHistoryWriter: HistoryWriterType, @unchecked Sendable {

    let server: ServerType

    public init(server: ServerType) {
        self.server = server
    }
    
    public func writePlay(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: true)
        Task {
            do {
                try await server.post(history: history)
                Log.d("wrote play of \(sha1)")
            } catch {
                Log.e("could not write play of \(sha1): \(error)")
            }
        }
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: false)
        Task {
            do {
                try await server.post(history: history)
                Log.d("wrote skip of \(sha1)")
            } catch {
                Log.e("could not write skip of \(sha1): \(error)")
            }
        }
    }
}

