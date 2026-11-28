import SwiftUI
import DJukeboxCommon

// this is used for writing locally played tracks to the history on the server
//
// @unchecked Sendable: implements the non-isolated HistoryWriterType and is called
// from the audio player's background callbacks; it only holds immutable references
// to Sendable collaborators. See the client concurrency note in AsyncAudioPlayer.
public class ServerHistoryWriter: HistoryWriterType, @unchecked Sendable {

    let server: ServerType

    // Reports whether the client is in offline / local-only mode. In offline mode the
    // server is unreachable, so a play/skip write can only time out ("The Request Timed
    // Out" on every track finish) — we keep it for later rather than firing a doomed
    // request. async because the source of truth (TrackFetcher.useLocalContentOnly) is
    // @MainActor and this writer is called from the player's non-isolated callbacks;
    // see the Client.swift wiring.
    let isOffline: @Sendable () async -> Bool

    private let pending: PendingHistoryQueue

    // `store` keeps plays/skips that can't be uploaded yet; without one they are
    // lost. `onPosted` is told about each entry the server accepts.
    public init(server: ServerType,
                store: LocalDatabase? = nil,
                isOffline: @escaping @Sendable () async -> Bool = { false },
                onPosted: @escaping @Sendable (ServerHistoryEntry) async -> Void = { _ in }) {
        self.server = server
        self.isOffline = isOffline
        self.pending = PendingHistoryQueue(server: server, store: store, onPosted: onPosted)
    }

    public func writePlay(of sha1: String, at date: Date) throws {
        record(sha1, at: date, fullyPlayed: true)
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        record(sha1, at: date, fullyPlayed: false)
    }

    // Upload anything recorded while the server was unavailable.
    public func drainPending() {
        Task {
            guard await !isOffline() else { return }
            await pending.drain()
        }
    }

    private func record(_ sha1: String, at date: Date, fullyPlayed: Bool) {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: fullyPlayed)
        Task {
            // no server URL configured, or playing offline: keep it for later
            let offline = await isOffline()
            await pending.record(history, online: !offline && server.hasServer)
        }
    }
}
