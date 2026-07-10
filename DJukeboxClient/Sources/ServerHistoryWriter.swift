import SwiftUI
import DJukeboxCommon

// this is used for writing locally played tracks to the history on the server
//
// @unchecked Sendable: implements the non-isolated HistoryWriterType and is called
// from the audio player's background callbacks; it only holds an immutable server
// reference and posts to it. See the client concurrency note in AsyncAudioPlayer.
public class ServerHistoryWriter: HistoryWriterType, @unchecked Sendable {

    let server: ServerType

    // Reports whether the client is in offline / local-only mode. In offline mode the
    // server is unreachable, so a play/skip write can only time out ("The Request Timed
    // Out" on every track finish) — we skip it rather than firing a doomed request.
    // async because the source of truth (TrackFetcher.useLocalContentOnly) is
    // @MainActor and this writer is called from the player's non-isolated callbacks;
    // see the Client.swift wiring.
    let isOffline: @Sendable () async -> Bool

    public init(server: ServerType,
                isOffline: @escaping @Sendable () async -> Bool = { false }) {
        self.server = server
        self.isOffline = isOffline
    }

    public func writePlay(of sha1: String, at date: Date) throws {
        // No server URL configured at all: nothing to record to (it was logging
        // a confusing "unsupported URL" error on every track finish).
        guard server.hasServer else { return }
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: true)
        Task {
            // A URL is configured but we're playing offline: skip the doomed write.
            guard await !isOffline() else { return }
            do {
                try await server.post(history: history)
                Log.d("wrote play of \(sha1)")
            } catch {
                Log.e("could not write play of \(sha1): \(error)")
            }
        }
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        // See writePlay: nothing to record with no server configured.
        guard server.hasServer else { return }
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: false)
        Task {
            // See writePlay: offline, so the write can only time out.
            guard await !isOffline() else { return }
            do {
                try await server.post(history: history)
                Log.d("wrote skip of \(sha1)")
            } catch {
                Log.e("could not write skip of \(sha1): \(error)")
            }
        }
    }
}

