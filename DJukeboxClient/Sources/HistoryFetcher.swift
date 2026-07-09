import Foundation
import SwiftUI
import DJukeboxCommon

// this is a view model used to update SwiftUI
public class HistoryEntry: Comparable, Identifiable, ObservableObject, Hashable {
    let track: AudioTrack
    let when: Date
    let playedFully: Bool

    public init(track: AudioTrack,
                when: Date,
                playedFully: Bool)
    {
        self.track = track
        self.when = when
        self.playedFully = playedFully
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(track)
        hasher.combine(when)
    }

    public static func < (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        return lhs.when < rhs.when
    }
    
    public static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        return lhs.track.SHA1 == rhs.track.SHA1 && lhs.when == rhs.when && lhs.playedFully == rhs.playedFully
    }
}

// @MainActor: a SwiftUI view model. AsyncAudioPlayer's hasPlay/hasSkip lookups
// are now `await`ed (both call sites are already async throws), so there's no
// non-isolated synchronous call-in left that would block this from being
// main-actor-isolated. See the client concurrency note in AsyncAudioPlayer.
@MainActor
public class HistoryFetcher: ObservableObject {
    @Published var all = PlayingHistory()
    @Published var recent: [HistoryEntry] = []

    var recentHistoryDurationSeconds: Double = 30*60*12 { // 60 minutes
        didSet(oldValue) {
            self.lastUpdateTime = nil
            self.refresh()
        }
    }

    func decrementHistoryAge() {
        self.recentHistoryDurationSeconds -= 60*60 
    }

    func incrementHistoryAge() {
        self.recentHistoryDurationSeconds += 60*60
    }
    
    let server: ServerType
    let trackFetcher: TrackFetcher
    
    var lastUpdateTime: Date?

    public init(withServer server: ServerType, trackFetcher: TrackFetcher) {
        self.server = server
        self.trackFetcher = trackFetcher
        refresh()
    }

    func eventCount(for hash: String) -> Int {
        let playsCount = self.plays(for: hash).count
        let skipsCount = self.skips(for: hash).count
        return playsCount + skipsCount
    }
    
    func plays(for hash: String) -> [Double] {
        if let plays = self.all.plays[hash] {
            return plays
        } else {
            return []
        }
    }

    public func hasPlay(for hash: String) -> Bool {
        return self.all.plays[hash] != nil
    }
    
    func skips(for hash: String) -> [Double] {
        if let skips = self.all.skips[hash]
        {
            return skips
        } else {
            return []
        }
    }

    public func hasSkip(for hash: String) -> Bool {
        return self.all.skips[hash] != nil
    }
    
    func updateRecent() {
        let previousHistoryDate = Date(timeIntervalSinceNow: -self.recentHistoryDurationSeconds)
        let recent = self.all.recentHistory(startingAt: previousHistoryDate)

        var history: [HistoryEntry] = []

        for (track, times) in recent.plays {
            if let audioTrack = trackFetcher.trackMap[track] { // XXX global trackFetcher
                for time in times {
                    history.append(HistoryEntry(track: audioTrack,
                                                when: Date(timeIntervalSince1970: time),
                                                playedFully: true))
                }
            }
        }
        for (track, times) in recent.skips {
            if let audioTrack = trackFetcher.trackMap[track] { // XXX global trackFetcher
                for time in times {
                    history.append(HistoryEntry(track: audioTrack,
                                                when: Date(timeIntervalSince1970: time),
                                                playedFully: false))
                }
            }
        }
        history.sort(by: >) // most recent first
        self.recent = history
    }

    // Apply an incremental history slice pushed over the /stream socket (the server
    // sends the new events whenever a play/skip is recorded), replacing the polling
    // that used to run every second. Merge (not replace): the socket only carries
    // recent deltas; the full history was loaded once by refresh() at init.
    public func ingest(_ history: PlayingHistory) {
        self.all = self.all.merge(with: history)
        self.lastUpdateTime = Date()
        self.updateRecent()
    }

    public func refresh() {
        // Offline / local-only: there is no server history to fetch, so don't
        // fire a request that can only fail and log noise at startup.
        guard server.hasServer else { return }
        if let lastUpdateTime = self.lastUpdateTime {
            let historyOverlapDuration: Double = 300
            let since = Int(lastUpdateTime.timeIntervalSince1970 - historyOverlapDuration)
            Task {
                do {
                    let history = try await server.listHistory(since: since)
                    self.all = self.all.merge(with: history)
                    self.updateRecent()
                } catch {
                    Log.e("could not refresh history: \(error)")
                }
            }
        } else {
            Task {
                do {
                    let history = try await server.listHistory()
                    // merge (not replace): a socket delta may have already
                    // landed before this initial full fetch completes
                    self.all = self.all.merge(with: history)
                    self.updateRecent()
                } catch {
                    Log.e("could not refresh history: \(error)")
                }
            }
        }
        self.lastUpdateTime = Date()
    }
}
