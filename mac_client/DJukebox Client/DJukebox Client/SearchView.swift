import SwiftUI

struct SearchView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    @State private var searchQuery: String = "" 

    var body: some View {
        VStack {
            HStack {
                Spacer()
                TextField(
                    "search here",
                    text: $searchQuery,
                    onEditingChanged: { foo in print("edit cha\(foo) \(self.searchQuery)") },
                    onCommit: { self.trackFetcher.search(for: self.searchQuery) }
                )
                Spacer()
            }
            List {
                ForEach(trackFetcher.searchResults, id: \.self) { track in
                    TrackDetail(track: track,
                                trackFetcher: self.trackFetcher,
                                audioPlayer: self.audioPlayer)
                }
            }
        }
    }
}
