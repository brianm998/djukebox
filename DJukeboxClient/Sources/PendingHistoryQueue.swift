import Foundation
import DJukeboxCommon

/// Uploads plays/skips to the server, holding them in the local database until
/// the server has accepted them. An actor so that only one drain runs at a time:
/// entries go up one by one, oldest first.
actor PendingHistoryQueue {
    private let server: ServerType
    private let store: LocalDatabase?

    // called for each entry the server accepts
    private let onPosted: @Sendable (ServerHistoryEntry) async -> Void

    // actors are reentrant at each await, so a second drain() could otherwise
    // post the row the first one is still posting
    private var draining = false

    init(server: ServerType,
         store: LocalDatabase?,
         onPosted: @escaping @Sendable (ServerHistoryEntry) async -> Void = { _ in })
    {
        self.server = server
        self.store = store
        self.onPosted = onPosted
    }

    /// Records one play/skip. When `online` it is uploaded right away (after any
    /// older pending entries); otherwise it waits for a later drain.
    func record(_ entry: ServerHistoryEntry, online: Bool) async {
        if let store, store.appendPendingHistory(entry) {
            if online { await drain() }
        } else if online {
            // nowhere to keep it, so one direct attempt is all there is
            _ = await post(entry)
        } else {
            Log.e("could not keep history for \(entry.hash)")
        }
    }

    /// Uploads pending entries in time order, stopping at the first failure so
    /// that entry and all later ones are retried by a later drain.
    func drain() async {
        guard let store, server.hasServer, !draining else { return }
        draining = true
        defer { draining = false }

        while let row = store.oldestPendingHistory() {
            guard await post(row.entry) else { return }
            // stop if the row is stuck, rather than posting it forever
            guard store.deletePendingHistory(id: row.id) else { return }
        }
    }

    private func post(_ entry: ServerHistoryEntry) async -> Bool {
        let kind = entry.fullyPlayed ? "play" : "skip"
        do {
            try await server.post(history: entry)
        } catch {
            Log.w("could not write \(kind) of \(entry.hash): \(error)")
            return false
        }
        Log.d("wrote \(kind) of \(entry.hash)")
        await onPosted(entry)
        return true
    }
}
