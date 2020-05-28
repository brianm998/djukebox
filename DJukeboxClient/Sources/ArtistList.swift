import SwiftUI
import DJukeboxCommon

struct BandList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var searchQuery: String = "" 

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }

    var body: some View {
        VStack {
            Spacer()
            HStack() {
                Text("Bands")
                if self.trackFetcher.allTracks.count > 0 {
                    Button(action: {
                               DispatchQueue.global().async {
                                   self.trackFetcher.cache(tracks: self.trackFetcher.allTracks)
                               }
                    }) {
                        Text("Cache All")
                    }
                }
            }
            HStack {
                Spacer()
                TextField("band search", text: $searchQuery)
            }
            List(trackFetcher.bands(matching: self.searchQuery)) { band in
                Text(band.Band)
                  .onTapGesture {
                      self.trackFetcher.showAlbums(forBand: band.Band)
                  }
            }
        }
    }
}
