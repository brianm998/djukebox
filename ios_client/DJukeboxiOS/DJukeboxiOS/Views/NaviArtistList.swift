import SwiftUI
import DJukeboxClient
import DJukeboxCommon

// The browse stack has two distinct push transitions that both key off an
// AudioTrack used as a representative row (artist-row -> that artist's albums,
// album-row -> that album's tracks). A bare `.navigationDestination(for:
// AudioTrack.self)` can't tell those apart from the value alone, so this route
// enum disambiguates which transition is meant. Attached once (see
// NaviArtistList's body, which roots the iPhone browse NavigationStack), it
// covers pushes from both this list and the NaviAlbumList it pushes to, since
// a `.navigationDestination` modifier applies to every push made further down
// the same stack from the point it's attached.
public enum BrowseRoute: Hashable {
    case albums(artist: AudioTrack)
    case tracks(album: AudioTrack)
}

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
                NavigationLink(value: BrowseRoute.albums(artist: artist)) {
                    Text(artist.Artist)
                      .foregroundStyle((self.trackFetcher.artistCacheStatus[artist.Artist] ?? .none).color)
                }
            }
            .djListChrome()
        }
        // Rooting this on NaviArtistList (the root of the iPhone browse
        // NavigationStack, see ContentView.tabView) means it covers both levels
        // of pushes: artist -> albums (handled right here) and, since the
        // modifier applies stack-wide from this point forward, albums -> tracks
        // pushed later from NaviAlbumList too.
        .navigationDestination(for: BrowseRoute.self) { route in
            switch route {
            case .albums(let artist):
                NaviAlbumList(self.client, artist: artist.Artist, title: artist.Artist)
            case .tracks(let album):
                NaviTrackList(self.client, album: album, title: album.Album ?? "")
            }
        }
    }
}
