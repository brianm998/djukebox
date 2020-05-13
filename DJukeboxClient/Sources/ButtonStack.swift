import SwiftUI
import DJukeboxCommon

struct PlayButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    var body: some View {
        Button(action: {
            self.audioPlayer.player?.resumePlaying() { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("play: \(audioTrack)")
                }
            }
        }) {
            #if os(iOS)
            Image(systemName: "play.fill")
            #else
            Text("\u{25B6}").font(.largeTitle)
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

struct PauseButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    var body: some View {
        Button(action: {
            self.audioPlayer.player?.pausePlaying() { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("pause: \(audioTrack)")
                }
            }
        }) {
            #if os(iOS)
            Image(systemName: "pause.fill")
            #else
            Text("\u{23F8}").font(.largeTitle)
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

struct SkipCurrentTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: {
                self.trackFetcher.audioPlayer.player?.stopPlayingTrack(withHash: self.trackFetcher.currentTrack?.SHA1 ?? "",
                                                         atIndex: -1) { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("skip: \(audioTrack)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            #if os(iOS)
            Image(systemName: "stop.fill")
            #else
            Text("\u{23F9}").font(.largeTitle) // stop
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

struct PlayRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: {
            self.trackFetcher.playRandomTrack()
        }) {
            Text("Random")
        }
    }
}

struct PlayNewRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: {
            self.trackFetcher.playNewRandomTrack()
        }) {
            Text("New Random")
        }
    }
}

struct ClearQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: { self.trackFetcher.clearPlayingQueue() }) {
            Text("Clear Queue")
              .foregroundColor(Color.red)
        }
    }
}

struct RefreshTracksFromServerButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: { self.trackFetcher.refreshTracks() }) {
            Text("Refresh")
        }
    }
}
struct RefreshQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: { self.trackFetcher.refreshQueue() }) {
            Text("Refresh Q")
        }
    }
}

