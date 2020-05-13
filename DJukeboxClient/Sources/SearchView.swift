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
                TextField("all text search", text: $searchQuery)
                Spacer()
            }
            List {
                ForEach(trackFetcher.search(for: self.searchQuery), id: \.self) { track in
                    TrackDetail(track: track,
                                trackFetcher: self.trackFetcher)
                }
            }
        }
    }
}
