import SwiftUI
import DJukeboxCommon

public struct ArtistList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var searchQuery: String = ""
    var client: Client

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.client = client
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack() {
                Text("Artists")
                if self.trackFetcher.allTracks.count > 0 {
                    let fetcher = trackFetcher
                    let action = {
                        DispatchQueue.global().async {
                            fetcher.cache(tracks: fetcher.allTracks)
                        }
                    }
                    Button(action: action) {
                        Text("Cache All")
                    }
                }
            }
            HStack {
                Spacer()
                TextField("artist search", text: $searchQuery)
                Button(action: {
                    self.searchQuery = ""
                }) {
                    Text("X")
                }
            }
            List(trackFetcher.artists(matching: self.searchQuery)) { artist in
                Text(artist.Artist)
                  .foregroundColor(DJTheme.textPrimary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture {
                      self.trackFetcher.showAlbums(forArtist: artist.Artist)
                  }
                  .artistTearOut(artist: artist.Artist)
            }
            .djListChrome()
        }
    }
}
