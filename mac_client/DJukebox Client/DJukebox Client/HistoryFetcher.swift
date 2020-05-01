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

    func refresh() {
        if let lastUpdateTime = self.lastUpdateTime {
            server.listHistory(since: Int(lastUpdateTime.timeIntervalSince1970)) { history, error in
                if let history = history {
                    if let allHistory = self.all {
                        let mergedHistory = allHistory.merge(with: history)
                        DispatchQueue.main.async {
                            self.all = mergedHistory
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.all = history
                        }
                    }
                }
            }
        } else {
            server.listHistory() { history, error in
                if let history = history {
                    DispatchQueue.main.async {
                        self.all = history
                    }
                }
            }
        }
        self.lastUpdateTime = Date()
    }
}
