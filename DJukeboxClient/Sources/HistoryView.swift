import SwiftUI

public struct HistoryView: View {

    @ObservedObject var historyFetcher: HistoryFetcher
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var isScrolledToTop = true

    private static let topAnchorID = "history-top-anchor"

    public init(_ client: Client) {
        self.historyFetcher = client.historyFetcher
        self.trackFetcher = client.trackFetcher
    }

    public var body: some View {
        VStack {
            HStack {
                Stepper(self.stepperText(), onIncrement: {
                    self.historyFetcher.incrementHistoryAge()
                }, onDecrement: {
                    self.historyFetcher.decrementHistoryAge()
                })
            }
            ScrollViewReader { proxy in
                List {
                    // zero-height sentinel used to detect/restore a top-of-list scroll position
                    Color.clear
                        .frame(height: 0)
                        .listRowInsets(EdgeInsets())
                        .onAppear { self.isScrolledToTop = true }
                        .onDisappear { self.isScrolledToTop = false }
                        .id(Self.topAnchorID)
                    ForEach(historyFetcher.recent, id: \.self) { historyEntry in
                        TrackDetail(track: historyEntry.track,
                                    trackFetcher: self.trackFetcher)
                    }
                }
                .onChange(of: historyFetcher.recent.count) { _ in
                    if self.isScrolledToTop {
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                }
            }
        }
    }

    func stepperText() -> String {
        let age = Int(historyFetcher.recentHistoryDurationSeconds)
        let start = "History for the last"
        if age < 120 {
            return "\(start) \(age) seconds"
        } else {
            return "\(start) \(age/60) minutes"
        }
    }
    
}
