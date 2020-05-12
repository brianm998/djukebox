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
                        self.trackFetcher.audioPlayer.player?.playRandomTrack(forBand: self.trackFetcher.albums[0].Band) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("Random")
                    }
                    Button(action: {
                        self.trackFetcher.audioPlayer.player?.playNewRandomTrack(forBand: self.trackFetcher.albums[0].Band) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("New Random")
                    }
                }
            }
            List(trackFetcher.albums) { band in
                Text(band.Album ?? "Singles") // XXX constant
                  .foregroundColor(band.Album == nil ? Color.red : Color.black)
                  .onTapGesture {
                      self.trackFetcher.showTracks(for: band)
                  }
            }
        }
    }
}

