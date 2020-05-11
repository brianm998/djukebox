import SwiftUI
import DJukeboxCommon

struct TrackDetail: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher
 
    var showDuration = true
    var playOnTap = true
    
    var body: some View {
        HStack(alignment: .center) {
            if layoutIsLarge() {
                Button(action: {
                           self.trackFetcher.showAlbums(forArtist: self.track.Artist)
                       }) {
                    Text(track.Artist).underline().foregroundColor(Color.blue)
                }.buttonStyle(PlainButtonStyle())
                if self.hasAlbum(track) {
                    Button(action: {
                               self.trackFetcher.showTracks(for: self.track)
                           }) {
                        Text(track.Album!).underline().foregroundColor(Color.blue)
                    }.buttonStyle(PlainButtonStyle())
                }
                Text(track.Title)
                if showDuration && track.Duration != nil {
                    Text(track.Duration!)
                }
            } else {
                VStack {
                    Button(action: {
                               self.trackFetcher.showAlbums(forArtist: self.track.Artist)
                           }) {
                        Text(track.Artist).underline().foregroundColor(Color.blue)
                    }.buttonStyle(PlainButtonStyle())
                    if self.hasAlbum(track) {
                        Button(action: {
                                   self.trackFetcher.showTracks(for: self.track)
                               }) {
                            Text(track.Album!).underline().foregroundColor(Color.blue)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
                Text(track.Title)
                if false && showDuration && track.Duration != nil {
                    Text(track.Duration!)
                }
            }
        }
          .onTapGesture {
              if self.playOnTap {
                  self.trackFetcher.audioPlayer.player?.playTrack(withHash: self.track.SHA1) { track, error in
                      self.trackFetcher.refreshQueue()
                      Log.d("track \(track) error \(error)")
                  }
              }
          }
    }
    
    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }
}

