import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviArtistList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var client: Client
    @State private var searchQuery: String = ""

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.client = client
    }

    public var body: some View {
        VStack(spacing: 8) {
            TextField("search here", text: $searchQuery)
                .textFieldStyle(.plain)
                .djField()
                .padding([.horizontal, .top])

            List(trackFetcher.artists(matching: self.searchQuery)) { (artist: AudioTrack) in
                NavigationLink(destination: NaviAlbumList(self.client,
                                                          artist: artist.Artist,
                                                          title: artist.Artist))
                {
                    Text(artist.Artist)
                      .foregroundColor((self.trackFetcher.artistCacheStatus[artist.Artist] ?? .none).color)
                }
            }
            .djListChrome()
        }
    }
}
