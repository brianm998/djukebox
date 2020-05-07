import SwiftUI

struct TrackDetail: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    var showDuration = true
    var playOnTap = true
    
    var body: some View {
        HStack(alignment: .center) {
            Button(action: {
                       self.trackFetcher.showAlbums(forArtist: self.track.Artist)
                   }) {
                Text(track.Artist)
            }
            if self.hasAlbum(track) {
                Button(action: {
                           self.trackFetcher.showTracks(for: self.track)
                       }) {
                    Text(track.Album!)
                }
            }
            Text(track.Title)
            if showDuration && track.Duration != nil {
                Text(track.Duration!)
            }
        }
          .onTapGesture {
            if self.playOnTap {
                  self.audioPlayer.player.playTrack(withHash: self.track.SHA1) { track, error in
                      self.trackFetcher.refreshQueue()
                      print("track \(track) error \(error)")
                  }
              }
          }
    }
    
    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }
}
