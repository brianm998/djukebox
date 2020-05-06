import SwiftUI

struct HistoryView: View {

    @ObservedObject var historyFetcher: HistoryFetcher
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
 
    var body: some View {
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
                                trackFetcher: self.trackFetcher,
                                audioPlayer: self.audioPlayer)
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
