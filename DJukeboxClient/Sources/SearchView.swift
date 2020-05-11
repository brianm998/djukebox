import SwiftUI
import DJukeboxCommon

public struct SearchView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var searchQuery: String = "" 
    
    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }

    public var body: some View {
        VStack {
            HStack {
                Spacer()
                TextField(
                    "search here",
                    text: $searchQuery,
                    onEditingChanged: { foo in Log.d("edit cha\(foo) \(self.searchQuery)") },
                    onCommit: { self.trackFetcher.search(for: self.searchQuery) }
                )
                Spacer()
            }
            List {
                ForEach(trackFetcher.searchResults, id: \.self) { track in
                    TrackDetail(track: track,
                                trackFetcher: self.trackFetcher)
                }
            }
        }
    }
}
