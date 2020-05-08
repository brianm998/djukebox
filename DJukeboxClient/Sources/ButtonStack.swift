import SwiftUI

struct PlayButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    var body: some View {
        Button(action: {
            self.audioPlayer.player?.resumePlaying() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else {
                    print("enqueued: \(audioTrack)")
                }
            }
        }) {
            Text("\u{25B6}").font(.largeTitle)
        }.buttonStyle(PlainButtonStyle())
    }
}

struct PauseButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    var body: some View {
        Button(action: {
            self.audioPlayer.player?.pausePlaying() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else {
                    print("enqueued: \(audioTrack)")
                }
            }
        }) {
            Text("\u{23F8}").font(.largeTitle)
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
                    print("DOH")
                } else {
                    print("enqueued: \(audioTrack)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            Text("\u{23F9}").font(.largeTitle) // stop
        }.buttonStyle(PlainButtonStyle())
    }
}

struct UseLocalQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: {
            try? self.trackFetcher.watch(queue: .local)
        }) {
            Text("Use Local")
        }//.buttonStyle(PlainButtonStyle())
    }
}

struct UseRemoteQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        Button(action: {
            try? self.trackFetcher.watch(queue: .remote)
        }) {
            Text("Use Remote")
        }//.buttonStyle(PlainButtonStyle())
    }
}

struct PlayRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.trackFetcher.audioPlayer.player?.playRandomTrack() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else if let audioTrack = audioTrack {
                    print("enqueued: \(audioTrack.Title)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            Text("Random")
              .frame(width: buttonWidth)
        }
    }
}

struct PlayNewRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.trackFetcher.audioPlayer.player?.playNewRandomTrack() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else if let audioTrack = audioTrack {
                    print("enqueued: \(audioTrack.Title)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            Text("New Random")
              .frame(width: buttonWidth)
        }
    }
}

struct ClearQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.trackFetcher.audioPlayer.player?.stopAllTracks() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else {
                    print("enqueued: \(audioTrack)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            Text("Clear Queue")
              .foregroundColor(Color.red)
              .frame(width: buttonWidth)
        }
    }
}

struct RefreshTracksFromServerButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: { self.trackFetcher.refreshTracks() }) {
            Text("Refresh")
              .frame(width: buttonWidth)
        }
    }
}
struct RefreshQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: { self.trackFetcher.refreshQueue() }) {
            Text("Refresh Q")
              .frame(width: buttonWidth)
        }
    }
}

