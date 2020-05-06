import Cocoa
import SwiftUI

// this is a view model used to update SwiftUI
public class HistoryEntry: Comparable, Identifiable, ObservableObject {
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
    
    public static func < (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        return lhs.when < rhs.when
    }
    
    public static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        return lhs.track.SHA1 == rhs.track.SHA1 && lhs.when == rhs.when && lhs.playedFully == rhs.playedFully
    }
}

public class HistoryFetcher: ObservableObject {
    @Published var all = PlayingHistory()
    @Published var recent: [HistoryEntry] = []

    var recentHistoryDurationSeconds: Double = 30*60 { // 60 minutes
        didSet(oldValue) {
            self.lastUpdateTime = nil
            self.refresh()
        }
    }

    func decrementHistoryAge() {
        self.recentHistoryDurationSeconds -= 60
    }

    func incrementHistoryAge() {
        self.recentHistoryDurationSeconds += 60
    }
    
    let server: ServerType
    let trackFetcher: TrackFetcher
    
    var lastUpdateTime: Date?

    init(withServer server: ServerType, trackFetcher: TrackFetcher) {
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
        history.sort()
        self.recent = history
    }

    func refresh() {
        if let lastUpdateTime = self.lastUpdateTime {
            let historyOverlapDuration: Double = 300
            server.listHistory(since: Int(lastUpdateTime.timeIntervalSince1970-historyOverlapDuration)) { history, error in
                if let history = history {
                    DispatchQueue.main.async {
                        self.all = self.all.merge(with: history)
                        self.updateRecent()
                    }
                }
            }
        } else {
            server.listHistory() { history, error in
                DispatchQueue.main.async {
                    if let history = history {
                        self.all = history
                        self.updateRecent()
                    }
                }
            }
        }
        self.lastUpdateTime = Date()
    }
}
