import SwiftUI
import DJukeboxCommon

public struct TrackDetail: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher

    var showDuration = true
    var playOnTap = true

    public init(track: AudioTrack,
                trackFetcher: TrackFetcher,
                showDuration: Bool = true,
                playOnTap: Bool = true)
    {
        self.track = track
        self.trackFetcher = trackFetcher
        self.showDuration = showDuration
        self.playOnTap = playOnTap
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            if layoutIsLarge() {
                Button(action: {
                           self.trackFetcher.showAlbums(forArtist: self.track.Credit)
                       }) {
                    Text(track.Credit).underline().foregroundStyle(DJTheme.neonCyan)
                }.buttonStyle(PlainButtonStyle())
                if self.hasAlbum(track) {
                    Button(action: {
                               self.trackFetcher.showTracks(for: self.track)
                           }) {
                        Text(track.Album!).underline().foregroundStyle(DJTheme.neonCyan)
                    }.buttonStyle(PlainButtonStyle())
                }
                Text(track.Title)
                if showDuration && track.Duration != nil {
                    Text(track.Duration!)
                }
            } else {
                VStack(alignment: .leading) {
                    Button(action: {
                               self.trackFetcher.showAlbums(forArtist: self.track.Credit)
                           }) {
                        Text(track.Credit).foregroundStyle(DJTheme.neonCyan)
                    }.buttonStyle(PlainButtonStyle())
                    if self.hasAlbum(track) {
                        Button(action: {
                                   self.trackFetcher.showTracks(for: self.track)
                               }) {
                            Text(track.Album!).underline().foregroundStyle(DJTheme.neonCyan)
                        }.buttonStyle(PlainButtonStyle())
                    }
                    Text(track.Title)
                    if false && showDuration && track.Duration != nil {
                        Text(track.Duration!)
                    }
                }
            }
        }
          .onTapGesture {
              if self.playOnTap {
                  Task {
                      do {
                          let track = try await self.trackFetcher.audioPlayer.player?.playTrack(withHash: self.track.SHA1)
                          Log.d("track \(track)")
                      } catch {
                          Log.e("could not play track: \(error)")
                      }
                      self.trackFetcher.refreshQueue()
                  }
              }
          }
    }
    
    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }
}

