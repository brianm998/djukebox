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
                    // cache(tracks:) already launches its own Task internally
                    // (TrackFetcher, F30/F20), so no manual dispatch is needed here.
                    Button(action: { trackFetcher.cache(tracks: trackFetcher.allTracks) }) {
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
                  .foregroundStyle((self.trackFetcher.artistCacheStatus[artist.Artist] ?? .none).color)
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
