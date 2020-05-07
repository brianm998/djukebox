import SwiftUI

struct TrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    @State private var dragging = false 
    
    var body: some View {
        VStack {
            Spacer()
            HStack() {
                Text(trackFetcher.trackTitle)
                if self.trackFetcher.tracks.count > 0 {
                    Button(action: {
                            self.audioPlayer.player.playTracks(self.trackFetcher.tracks) { success, error in
                            self.trackFetcher.refreshQueue()
                        }
                    }) {
                        Text("Play All")
                    }

                    //.alignmentGuide(.trailing, computeValue: { d in d[.trailing] } )
                }
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor(self.historyFetcher.eventCount(for: track.SHA1) == 0 ? Color.green : Color.gray)
                  .onTapGesture {
                      self.audioPlayer.player.playTrack(withHash: track.SHA1) { track, error in
                          self.trackFetcher.refreshQueue()
                          print("track \(track) error \(error)")
                      }
                  }
                  .onDrag {
                      let provider = NSItemProvider(object: track.SHA1 as NSString)
                      provider.suggestedName = track.Title
                      return provider
                  }
            }
        }
          .gesture(
            DragGesture(minimumDistance: 100)
              .onChanged { value in
                  print("onChanged value \(value)")
                  if !self.dragging {
                      #if os(macOS)
                      self.makeNewWindow(atOrigin: value.location)
                      #endif
                      self.dragging = true
                  }
              }
              .onEnded { value in
                  print("onEnded value \(value)")
                  self.dragging = false
              }
          )
    }

    #if os(macOS)
    fileprivate func makeNewWindow(atOrigin origin: CGPoint) {
        let trackFetcher = TrackFetcher(withServer: self.serverConnection)
        trackFetcher.audioPlayer = self.audioPlayer.player
        trackFetcher.tracks = self.trackFetcher.tracks
        trackFetcher.desiredArtist = self.trackFetcher.desiredArtist
        trackFetcher.desiredAlbum = self.trackFetcher.desiredAlbum

        if let artist = trackFetcher.desiredArtist {
            if let album = trackFetcher.desiredAlbum {
                trackFetcher.trackTitle = "\(artist) \(album) songs"
            } else {
                trackFetcher.trackTitle = "\(artist) singles"
            }
        } else {
            trackFetcher.trackTitle = "FIX THIS!"
        }
        let contentView = TrackList(trackFetcher: trackFetcher,
                                    historyFetcher: historyFetcher,
                                    serverConnection: self.serverConnection,
                                    audioPlayer: audioPlayer)
        var window = NSWindow(
          contentRect: NSRect(x: origin.x, y: origin.y, // this position is ignored :(
                              width: 250, height: 300), 
          styleMask: [.titled, .closable, .utilityWindow, .resizable],
          backing: .buffered, defer: false)
        window.center()
        //window.setFrameAutosaveName("Utility Window")
        window.contentView = NSHostingView(rootView: contentView)
        //        window.makeKeyAndOrderFront(nil)
        window.setIsVisible(true)
        windows.append(window)
    }
    #endif
}

#if os(macOS)
// this is only here to avoid an autorelease crash upon release of sub-windows
fileprivate var windows: [NSWindow] = [] 
#endif

