import SwiftUI
import DJukeboxCommon

struct BandList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var searchQuery: String = "" 
    var client: Client

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.client = client
    }

    var body: some View {
        VStack {
            Spacer()
            HStack() {
                Text("Bands")
                if self.trackFetcher.allTracks.count > 0 {
                    let action = {
                        DispatchQueue.global().async {
                            self.trackFetcher.cache(tracks: self.trackFetcher.allTracks)
                        }
                    }
                    Button(action: action) {
                        Text("Cache All")
                    }
                }
            }
            HStack {
                Spacer()
                TextField("band search", text: $searchQuery)
                Button(action: {
                    self.searchQuery = ""
                }) {
                    Text("X")
                }
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
