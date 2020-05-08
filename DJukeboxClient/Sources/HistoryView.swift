import SwiftUI

public struct HistoryView: View {

    @ObservedObject var historyFetcher: HistoryFetcher
    @ObservedObject var trackFetcher: TrackFetcher

    public init(historyFetcher: HistoryFetcher,
                trackFetcher: TrackFetcher)
    {
        self.historyFetcher = historyFetcher
        self.trackFetcher = trackFetcher
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
            List {
                ForEach(historyFetcher.recent, id: \.self) { historyEntry in
                    TrackDetail(track: historyEntry.track,
                                trackFetcher: self.trackFetcher)
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
