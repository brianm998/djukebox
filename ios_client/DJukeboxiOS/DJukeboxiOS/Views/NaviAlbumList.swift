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
                  .foregroundStyle((self.trackFetcher.albumCacheStatus[TrackFetcher.albumStatusKey(artist: album.Artist, album: album.Album)] ?? .none).color)
            }
        }
          .djListChrome()
          .navigationTitle(Text(title))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                  Menu {
                      Button {
                          Task {
                              do {
                                  _ = try await self.trackFetcher.audioPlayer.player?.playNewRandomTrack(forArtist: self.artist)
                              } catch {
                                  Log.e("could not play new random track: \(error)")
                              }
                              self.trackFetcher.refreshQueue()
                          }
                      } label: {
                          Label("Play New Random Track", systemImage: "shuffle")
                      }
                      Button {
                          Task {
                              do {
                                  _ = try await self.trackFetcher.audioPlayer.player?.playRandomTrack(forArtist: self.artist)
                              } catch {
                                  Log.e("could not play random track: \(error)")
                              }
                              self.trackFetcher.refreshQueue()
                          }
                      } label: {
                          Label("Play Random Track", systemImage: "shuffle")
                      }
                      Button {
                          self.trackFetcher.cacheTracks(forArtist: self.artist)
                      } label: {
                          Label("Cache All", systemImage: "arrow.down.circle")
                      }
                  } label: {
                      Image(systemName: "plus").imageScale(.large)
                  }
              }
          }
    }
}
