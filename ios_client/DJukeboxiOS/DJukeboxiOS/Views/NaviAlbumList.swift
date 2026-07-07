import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviAlbumList: View {
    var client: Client
    // Observe the fetcher and derive the album list from the live catalog, keyed
    // by artist name, rather than freezing a snapshot at navigation time — otherwise
    // a catalog change (e.g. switching to local/offline) can't refresh this view.
    @ObservedObject var trackFetcher: TrackFetcher
    let artist: String
    let title: String
    @State private var showingActionSheet = false

    public init(_ client: Client, artist: String, title: String) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.artist = artist
        self.title = title
    }

    public var body: some View {
        let albums = trackFetcher.albums(forArtist: artist)
        return List(albums) { album in
            NavigationLink( destination: NaviTrackList(self.client,
                                                       album: album,
                                                       title: album.Album ?? ""))
            {
                Text(album.Album ?? "")
                  .foregroundColor((self.trackFetcher.albumCacheStatus[TrackFetcher.albumStatusKey(artist: album.Artist, album: album.Album)] ?? .none).color)
            }
        }
          .djListChrome()
          .navigationBarTitle(Text(title), displayMode: .inline)
          .navigationBarItems(trailing:
                                Button(action: {self.showingActionSheet = true }) {
                                    Image(systemName: "plus").imageScale(.large)
                                })
          .actionSheet(isPresented: $showingActionSheet) {
              ActionSheet(title: Text(""),
                          buttons: [
                            .default(Text("Cache All")) {
                                self.trackFetcher.cacheTracks(forArtist: self.artist)
                            },
                            .default(Text("Play New Random Track")) {
                                self.trackFetcher.audioPlayer.player?.playNewRandomTrack(forArtist: self.artist) { success, error in
                                    self.trackFetcher.refreshQueue()
                                }
                            },
                            .default(Text("Play Random Track")) {
                                self.trackFetcher.audioPlayer.player?.playRandomTrack(forArtist: self.artist) { success, error in
                                    self.trackFetcher.refreshQueue()
                                }
                            },
                            .cancel()
                          ])
          }
    }
}
