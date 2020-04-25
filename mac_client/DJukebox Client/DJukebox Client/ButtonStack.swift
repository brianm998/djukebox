import SwiftUI

struct PausePlayButton: View {

    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    var body: some View {
        Button(action: {
            if self.serverConnection.isPaused {
                self.serverConnection.resumePlaying() { audioTrack, error in
                    if let error = error {
                        print("DOH")
                    } else {
                        print("enqueued: \(audioTrack)")
                    }
                }
            } else {
                self.serverConnection.pausePlaying() { audioTrack, error in
                    if let error = error {
                        print("DOH")
                    } else {
                        print("enqueued: \(audioTrack)")
                    }
                }
            }
        }) {
            // play / pause
            Text(self.serverConnection.isPaused ? "\u{25B6}" : "\u{23F8}").font(.largeTitle) 
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

struct ButtonStack: View {

    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    let buttonWidth: CGFloat = 80
    
    var body: some View {
        VStack(alignment: .trailing) {
            HStack(alignment: .top) {
                SkipCurrentTrackButton(trackFetcher: trackFetcher,
                                       serverConnection: self.serverConnection)
                PausePlayButton(serverConnection: self.serverConnection)
            }        

            PlayRandomTrackButton(trackFetcher: trackFetcher,
                                  serverConnection: self.serverConnection,
                                  buttonWidth: buttonWidth)

            ClearQueueButton(trackFetcher: trackFetcher,
                             serverConnection: self.serverConnection,
                             buttonWidth: buttonWidth)

            RefreshTracksFromServerButton(trackFetcher: trackFetcher,
                                          buttonWidth: buttonWidth)

            RefreshQueueButton(trackFetcher: trackFetcher,
                               buttonWidth: buttonWidth)
        }        
    }
}

