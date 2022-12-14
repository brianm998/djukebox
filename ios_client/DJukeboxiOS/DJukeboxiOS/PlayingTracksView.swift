import SwiftUI
import DJukeboxCommon
import DJukeboxClient

public struct VerticalPlayingTimeRemainingView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        return VStack {
            Text(format(duration: trackFetcher.totalDuration))
            Text(string(forTime: trackFetcher.completionTime))
        }
    }
}

public struct HorizontalPlayingTimeRemainingView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        return HStack {
            Text(format(duration: trackFetcher.totalDuration))
            Text(string(forTime: trackFetcher.completionTime))
        }
    }
}


// used on the iPad
public struct BigButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        let offlineToggle = Binding<Bool>(get: { self.trackFetcher.useLocalContentOnly },
                                          set: { self.trackFetcher.useLocalContentOnly = $0 })

        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })

        return
          VStack(alignment: .leading) {
              HStack {
                  SkipCurrentTrackButton(trackFetcher: self.trackFetcher)
                  
                  if(self.trackFetcher.audioPlayer.isPaused) {
                      PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
                  } else {
                      PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
                  }

                  if trackFetcher.totalDuration > 0 {
                      VerticalPlayingTimeRemainingView(trackFetcher: trackFetcher)
                  }

                  PlayRandomTrackButton(trackFetcher: trackFetcher)
                  PlayNewRandomTrackButton(trackFetcher: trackFetcher)
                  ShuffleQueueButton(trackFetcher: trackFetcher)
                  Button(action: {
                       self.trackFetcher.cacheQueue()
                   }) {
                      Text("Cache Q")
                        .underline().foregroundColor(Color.blue)
                  }
                  ClearQueueButton(trackFetcher: trackFetcher)
              }
              HStack {
                  /*
                   Button(action: {
                   self.trackFetcher.clearCache()
                   }) {
                   Text("Clear Cache")
                   .underline().foregroundColor(Color.red)
                   }
                   */
                  Text("Offline:")
                  Toggle("", isOn: offlineToggle).labelsHidden()

                  Group {
                      VStack {
                          HStack {
                              Text("Play Local:")
                              Toggle("", isOn: localPlayToggle).labelsHidden()
                          }
                      }

                      RefreshTracksFromServerButton(trackFetcher: trackFetcher)
                      RefreshQueueButton(trackFetcher: trackFetcher)

                      Spacer()
                  }
              }
          }
    }
}

public struct SmallButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var showingActionSheet = false
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        let offlineToggle = Binding<Bool>(get: { self.trackFetcher.useLocalContentOnly },
                                          set: { self.trackFetcher.useLocalContentOnly = $0 })
        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })
        return VStack {

                HStack {
                    Text("Actions")
                      .underline().foregroundColor(Color.blue)
                      .onTapGesture { self.showingActionSheet = true }
                      .actionSheet(isPresented: $showingActionSheet) {
                          ActionSheet(title: Text(""),
                                      //message: Text(""),
                                      buttons: [
                                        .default(Text("Play New Random Track")) { self.trackFetcher.playNewRandomTrack() },
                                        .default(Text("Play Random Track")) { self.trackFetcher.playRandomTrack() },
                                        .default(Text("Refresh Queue")) { self.trackFetcher.refreshQueue() },
                                        .default(Text("Refresh Tracks")) { self.trackFetcher.refreshTracks() },
                                        .default(Text("Cache Current Queue")) { self.trackFetcher.cacheQueue() },
                                        .destructive(Text("Clear Cache")) { self.trackFetcher.clearCache() },
                                        .destructive(Text("Clear Queue")) { self.trackFetcher.clearPlayingQueue() },
                                        .cancel()
                                      ])
                      }
                    Text("Offline:")
                    Toggle("", isOn: offlineToggle).labelsHidden()
                }
                    
                HStack {
                    SkipCurrentTrackButton(trackFetcher: self.trackFetcher)
                    
                    if(self.trackFetcher.playingQueue?.isPaused ?? false) {
                        PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
                    } else {
                        PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
                    }

                    VStack {
                        HStack {
                            Text("Play Local:")
                            Toggle("", isOn: localPlayToggle).labelsHidden()
                        }
                    }
                }

                
                HStack {
                    Spacer()
                    if trackFetcher.totalDuration > 0 {
                        HorizontalPlayingTimeRemainingView(trackFetcher: trackFetcher)
                    }
                }
        }
    }
}
    
public struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }
    
    public var body: some View {
        
        VStack(alignment: .leading) {
            if layoutIsLarge() {
                BigButtonView(trackFetcher: trackFetcher)
            } else {
                SmallButtonView(trackFetcher: trackFetcher)
            }
            PlayingTrackView(trackFetcher: trackFetcher)
            PlayingQueueView(trackFetcher: trackFetcher)
        }
    }
}



