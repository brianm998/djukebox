import SwiftUI
import DJukeboxCommon

#if os(macOS)

// XXX should split this out into two separate mac and iOS files

public struct TrackList: View {
    var client: Client
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }

    public var body: some View {
        return VStack {
            Spacer()
            HStack() {
                Text(trackFetcher.trackTitle)
                if self.trackFetcher.tracks.count > 0 {
                    Button(action: {
                            self.trackFetcher.audioPlayer.player?.playTracks(self.trackFetcher.tracks) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("Play All")
                    }
                    // download every track shown here for offline playback
                    Button(action: {
                        self.trackFetcher.cache(tracks: self.trackFetcher.tracks)
                    }) {
                        Text("Cache All")
                    }
                }
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor(self.client.historyFetcher.eventCount(for: track.SHA1) == 0 ? DJTheme.neonCyan : DJTheme.textSecondary)
                  .onTapGesture {
                      self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { track, error in
                          self.trackFetcher.refreshQueue()
                          Log.d("track \(track) error \(error)")
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

#else
// XXX MIDDLE

public struct TrackList: View {
    var client: Client
    @ObservedObject var trackFetcher: TrackFetcher

    @State private var showingActionSheet = false

    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }

    public var body: some View {
        return VStack {
            Spacer()
            HStack() {
                Text(trackFetcher.trackTitle)
                if self.trackFetcher.tracks.count > 0 {

                    Button(action: {self.showingActionSheet = true }) {
                        Image(systemName: "plus").imageScale(.large)
                    }
                }
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor(self.client.historyFetcher.eventCount(for: track.SHA1) == 0 ? DJTheme.neonCyan : DJTheme.textSecondary)
                  .onTapGesture {
                      self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { track, error in
                          self.trackFetcher.refreshQueue()
                          Log.d("track \(track) error \(error)")
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
          .actionSheet(isPresented: $showingActionSheet) {
              ActionSheet(title: Text(""),
                          buttons: [
                            .default(Text("Play All")) {
                                self.client.trackFetcher.audioPlayer.player?.playTracks(self.trackFetcher.tracks.sorted()) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                }
                            },
                            .default(Text("Cache All")) {
                                self.client.trackFetcher.cache(tracks: self.trackFetcher.tracks)
                            },
                            .cancel()
                          ])
          }
    }
}

#endif
