import SwiftUI

struct AlbumList: View {
    @ObservedObject var client: Client
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text(trackFetcher.albumTitle)
                if self.trackFetcher.albums.count > 0 {
                    Button(action: {
                        self.trackFetcher.audioPlayer.player?.playRandomTrack(forArtist: self.trackFetcher.albums[0].Artist) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("Random")
                    }
                    Button(action: {
                        self.trackFetcher.audioPlayer.player?.playNewRandomTrack(forArtist: self.trackFetcher.albums[0].Artist) { success, error in
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

