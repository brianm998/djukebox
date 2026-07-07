import SwiftUI

public struct AlbumList: View {
    let client: Client
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }

    public var body: some View {
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
                  .foregroundColor((self.trackFetcher.albumCacheStatus[TrackFetcher.albumStatusKey(artist: artist.Artist, album: artist.Album)] ?? .none).color)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture {
                      self.trackFetcher.showTracks(for: artist)
                  }
                  .albumTearOut(artist: artist.Artist, album: artist.Album)
            }
            .djListChrome()
        }
    }
}

