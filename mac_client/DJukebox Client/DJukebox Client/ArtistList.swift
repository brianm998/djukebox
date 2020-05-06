import SwiftUI

struct ArtistList: View {
    @ObservedObject var trackFetcher: TrackFetcher

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
