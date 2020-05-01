import Cocoa
import SwiftUI

// this is a view model used to update SwiftUI

public class HistoryFetcher: ObservableObject {
    @Published var all: PlayingHistory?

    let server: ServerType
    var lastUpdateTime: Date?

    init(withServer server: ServerType) {
        self.server = server
        refresh()
    }

    func eventCount(for hash: String) -> Int {
        let playsCount = self.plays(for: hash).count
        let skipsCount = self.skips(for: hash).count
        return playsCount + skipsCount
    }
    
    func plays(for hash: String) -> [Double] {
        if let history = self.all,
           let plays = history.plays[hash]
        {
            return plays
        } else {
            return []
        }
    }

    func skips(for hash: String) -> [Double] {
        if let history = self.all,
           let skips = history.skips[hash]
        {
            return skips
        } else {
            return []
        }
    }

    func refresh() {
        if let lastUpdateTime = self.lastUpdateTime {
            let historyOverlapDuration = 300
            server.listHistory(since: Int(lastUpdateTime.timeIntervalSince1970-historyOverlapDuration)) { history, error in
                if let history = history {
                    DispatchQueue.main.async {
                        if let allHistory = self.all {
                            self.all = allHistory.merge(with: history)
                        } else {
                            self.all = history
                        }
                    }
                }
            }
        } else {
            server.listHistory() { history, error in
                DispatchQueue.main.async {
                    if let history = history { self.all = history }
                }
            }
        }
        self.lastUpdateTime = Date()
    }
}
