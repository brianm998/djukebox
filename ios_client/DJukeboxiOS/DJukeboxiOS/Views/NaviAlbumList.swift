import SwiftUI
import DJukeboxClient

public struct NaviAlbumList: View {
    var client: Client
    let bands: [AudioTrack]
    let title: String
    @State private var showingActionSheet = false
    
    public init(_ client: Client, bands: [AudioTrack], title: String) {
        self.client = client
        self.bands = bands
        self.title = title
    }

    public var body: some View {
        List(self.bands) { band in
            NavigationLink( destination: NaviTrackList(self.client,
                                                       tracks: self.client.trackFetcher.tracks(for: band).sorted(),
                                                       title: band.Album ?? ""))
            {
                Text(band.Album ?? "")
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
                                self.client.trackFetcher.cacheTracks(forBand: self.bands[0].Band)
                            },
                            .default(Text("Play New Random Track")) {
                                self.client.trackFetcher.audioPlayer.player?.playNewRandomTrack(forBand: self.bands[0].Band) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                }
                            },
                            .default(Text("Play Random Track")) {
                                self.client.trackFetcher.audioPlayer.player?.playRandomTrack(forBand: self.bands[0].Band) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                }
                            },
                            .cancel()
                          ])
          }
    }
}
