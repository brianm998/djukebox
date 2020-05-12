import SwiftUI

struct BandList: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }

    var body: some View {
        VStack {
            Spacer()
            Text("Bands")
            List(trackFetcher.bands) { band in
                Text(band.Band)
                  .onTapGesture {
                      self.trackFetcher.showAlbums(forBand: band.Band)
                  }
            }
        }
    }
}
