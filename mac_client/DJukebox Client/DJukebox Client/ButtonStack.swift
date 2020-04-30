import SwiftUI

struct PlayButton: View {
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    var body: some View {
        Button(action: {
            self.serverConnection.resumePlaying() { audioTrack, error in
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
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    var body: some View {
        Button(action: {
            self.serverConnection.pausePlaying() { audioTrack, error in
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
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    var body: some View {
        Button(action: {
            self.serverConnection.stopPlayingTrack(withHash: self.trackFetcher.currentTrack?.SHA1 ?? "") { audioTrack, error in
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

struct PlayRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.serverConnection.playRandomTrack() { audioTrack, error in
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
    @ObservedObject var serverConnection: ServerConnection //ServerType
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.serverConnection.playNewRandomTrack() { audioTrack, error in
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
    @ObservedObject var serverConnection: ServerConnection //ServerType
    var buttonWidth: CGFloat
    
    var body: some View {
        Button(action: {
            self.serverConnection.stopAllTracks() { audioTrack, error in
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

