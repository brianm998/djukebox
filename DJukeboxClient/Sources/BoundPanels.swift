//
//  BoundPanels.swift
//  DJukeboxClient
//
//  Browse panels pinned to a fixed scope (created by dragging an artist/album into
//  a window). Unlike AlbumList/TrackList they don't follow the window's live
//  browse cascade — they derive their list from the shared catalog for their fixed
//  artist/album. Tapping still drives the window's cascade / plays, as usual.
//

#if os(macOS)
import SwiftUI
import DJukeboxCommon

public struct BoundAlbumList: View {
    let client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    let artist: String

    public init(_ client: Client, artist: String) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.artist = artist
    }

    public var body: some View {
        VStack {
            HStack {
                Text(artist).foregroundStyle(DJTheme.textPrimary)
                Spacer()
            }.padding(.horizontal, 4)
            List(trackFetcher.albums(forArtist: artist)) { album in
                Text(album.Album ?? "Singles")
                  .foregroundStyle((self.trackFetcher.albumCacheStatus[TrackFetcher.albumStatusKey(artist: album.Artist, album: album.Album)] ?? .none).color)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture { self.trackFetcher.showTracks(for: album) }
                  .albumTearOut(artist: album.Artist, album: album.Album)
            }
            .djListChrome()
        }
    }
}

public struct BoundTrackList: View {
    let client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    let artist: String
    let album: String?

    public init(_ client: Client, artist: String, album: String?) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.artist = artist
        self.album = album
    }

    public var body: some View {
        let tracks = trackFetcher.tracks(forArtist: artist, album: album)
        return VStack {
            HStack {
                Text(album ?? "\(artist) singles").foregroundStyle(DJTheme.textPrimary)
                if tracks.count > 0 {
                    Button("Play All") {
                        Task {
                            do {
                                _ = try await self.trackFetcher.audioPlayer.player?.playTracks(tracks)
                            } catch {
                                Log.e("could not play all tracks: \(error)")
                            }
                            self.trackFetcher.refreshQueue()
                        }
                    }
                }
                Spacer()
            }.padding(.horizontal, 4)
            List(tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundStyle((self.trackFetcher.cachedTrackSHA1s.contains(track.SHA1) ? CacheStatus.full : .none).color)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture {
                      Task {
                          do {
                              _ = try await self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1)
                          } catch {
                              Log.e("could not play track: \(error)")
                          }
                          self.trackFetcher.refreshQueue()
                      }
                  }
                  .draggable(TrackDragItem(sha1: track.SHA1))
            }
            .djListChrome()
        }
    }
}
#endif
