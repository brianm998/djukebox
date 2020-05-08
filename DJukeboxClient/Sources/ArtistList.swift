import SwiftUI

struct ArtistList: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }

    var body: some View {
        VStack {
            Spacer()
            Text("Artists")
            List(trackFetcher.artists) { artist in
                Text(artist.Artist)
                  .onTapGesture {
                      self.trackFetcher.showAlbums(forArtist: artist.Artist)
                  }
            }
        }
    }
}
