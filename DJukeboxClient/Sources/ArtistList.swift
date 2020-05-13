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
            Text("Bands")
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
