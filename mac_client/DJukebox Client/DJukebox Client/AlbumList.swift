import SwiftUI

struct AlbumList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text(trackFetcher.albumTitle)
                if self.trackFetcher.albums.count > 0 {
                    Button(action: {
                        self.audioPlayer.player.playRandomTrack(forArtist: self.trackFetcher.albums[0].Artist) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("Random")
                    }
                    Button(action: {
                        self.audioPlayer.player.playNewRandomTrack(forArtist: self.trackFetcher.albums[0].Artist) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("New Random")
                    }
                }
            }
            List(trackFetcher.albums) { artist in
                Text(artist.Album ?? "Singles") // XXX constant
                  .foregroundColor(artist.Album == nil ? Color.red : Color.black)
                  .onTapGesture {
                      self.trackFetcher.showTracks(for: artist)
                  }
            }
        }
    }
}

