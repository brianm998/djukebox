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
                        Task {
                            do {
                                _ = try await self.trackFetcher.audioPlayer.player?.playTracks(self.trackFetcher.tracks)
                            } catch {
                                Log.e("could not play all tracks: \(error)")
                            }
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
                  .foregroundColor((self.trackFetcher.cachedTrackSHA1s.contains(track.SHA1) ? CacheStatus.full : .none).color)
                  .onTapGesture {
                      Task {
                          do {
                              let playedTrack = try await self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1)
                              Log.d("track \(playedTrack)")
                          } catch {
                              Log.e("could not play track: \(error)")
                          }
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

#else
// XXX MIDDLE

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

                    Menu {
                        Button {
                            Task {
                                do {
                                    _ = try await self.client.trackFetcher.audioPlayer.player?.playTracks(self.trackFetcher.tracks.sorted())
                                } catch {
                                    Log.e("could not play all tracks: \(error)")
                                }
                                self.client.trackFetcher.refreshQueue()
                            }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                        Button {
                            self.client.trackFetcher.cache(tracks: self.trackFetcher.tracks)
                        } label: {
                            Label("Cache All", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus").imageScale(.large)
                    }
                }
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor((self.trackFetcher.cachedTrackSHA1s.contains(track.SHA1) ? CacheStatus.full : .none).color)
                  .onTapGesture {
                      Task {
                          do {
                              let playedTrack = try await self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1)
                              Log.d("track \(playedTrack)")
                          } catch {
                              Log.e("could not play track: \(error)")
                          }
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
