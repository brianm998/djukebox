import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviAlbumList: View {
    var client: Client
    // Observe the fetcher and derive the album list from the live catalog, keyed
    // by band name, rather than freezing a snapshot at navigation time — otherwise
    // a catalog change (e.g. switching to local/offline) can't refresh this view.
    @ObservedObject var trackFetcher: TrackFetcher
    let band: String
    let title: String
    @State private var showingActionSheet = false

    public init(_ client: Client, band: String, title: String) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.band = band
        self.title = title
    }

    public var body: some View {
        let albums = trackFetcher.albums(forBand: band)
        return List(albums) { album in
            NavigationLink( destination: NaviTrackList(self.client,
                                                       album: album,
                                                       title: album.Album ?? ""))
            {
                Text(album.Album ?? "")
            }
        }
          .navigationBarTitle(Text(title), displayMode: .inline)
          .navigationBarItems(trailing:
                                Button(action: {self.showingActionSheet = true }) {
                                    Image(systemName: "plus").imageScale(.large)
                                })
          .actionSheet(isPresented: $showingActionSheet) {
              ActionSheet(title: Text(""),
                          buttons: [
                            .default(Text("Cache All")) {
                                self.trackFetcher.cacheTracks(forBand: self.band)
                            },
                            .default(Text("Play New Random Track")) {
                                self.trackFetcher.audioPlayer.player?.playNewRandomTrack(forBand: self.band) { success, error in
                                    self.trackFetcher.refreshQueue()
                                }
                            },
                            .default(Text("Play Random Track")) {
                                self.trackFetcher.audioPlayer.player?.playRandomTrack(forBand: self.band) { success, error in
                                    self.trackFetcher.refreshQueue()
                                }
                            },
                            .cancel()
                          ])
          }
    }
}
