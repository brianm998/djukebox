import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviTrackList: View {
    var client: Client
    let tracks: [AudioTrack]
    let title: String
    @State private var showingActionSheet = false
    
    public init(_ client: Client, tracks: [AudioTrack], title: String) {
        self.client = client
        self.tracks = tracks
        self.title = title
    }

    public var body: some View {
        List(self.tracks) { track in
            Text(track.Title)
              .onTapGesture {
                  self.client.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { track, error in
                      Log.d("")
                      // should show some message here
                  }
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
                            .default(Text("Play All")) {
                                self.client.trackFetcher.audioPlayer.player?.playTracks(self.tracks) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                }
                            },
                            .default(Text("Cache All Locally")) {
                                self.client.trackFetcher.cache(tracks: self.tracks)
                            },
                            .cancel()
                          ]
              )
          }
    }
}
