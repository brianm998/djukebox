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
    let band: String

    public init(_ client: Client, band: String) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.band = band
    }

    public var body: some View {
        VStack {
            HStack {
                Text(band).foregroundColor(DJTheme.textPrimary)
                Spacer()
            }.padding(.horizontal, 4)
            List(trackFetcher.albums(forBand: band)) { album in
                Text(album.Album ?? "Singles")
                  .foregroundColor(album.Album == nil ? DJTheme.neonMagenta : DJTheme.textPrimary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture { self.trackFetcher.showTracks(for: album) }
                  .albumTearOut(band: album.Band, album: album.Album)
            }
            .djListChrome()
        }
    }
}

public struct BoundTrackList: View {
    let client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    let band: String
    let album: String?

    public init(_ client: Client, band: String, album: String?) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.band = band
        self.album = album
    }

    public var body: some View {
        let tracks = trackFetcher.tracks(forBand: band, album: album)
        return VStack {
            HStack {
                Text(album ?? "\(band) singles").foregroundColor(DJTheme.textPrimary)
                if tracks.count > 0 {
                    Button("Play All") {
                        self.trackFetcher.audioPlayer.player?.playTracks(tracks) { _, _ in
                            self.trackFetcher.refreshQueue()
                        }
                    }
                }
                Spacer()
            }.padding(.horizontal, 4)
            List(tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor(self.client.historyFetcher.eventCount(for: track.SHA1) == 0 ? DJTheme.neonCyan : DJTheme.textSecondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture {
                      self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { _, _ in
                          self.trackFetcher.refreshQueue()
                      }
                  }
                  .onDrag {
                      let provider = NSItemProvider(object: track.SHA1 as NSString)
                      provider.suggestedName = track.Title
                      return provider
                  }
            }
            .djListChrome()
        }
    }
}
#endif
