import SwiftUI
import DJukeboxCommon

struct TrackList: View {
    var client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var dragging = false
    
    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }
    
    var body: some View {
        VStack {
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

                    //.alignmentGuide(.trailing, computeValue: { d in d[.trailing] } )
                }
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .foregroundColor(self.client.historyFetcher.eventCount(for: track.SHA1) == 0 ? Color.green : Color.gray)
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
        }
          .gesture(
            DragGesture(minimumDistance: 100)
              .onChanged { value in
                  Log.d("onChanged value \(value)")
                  if !self.dragging {
                      #if os(macOS)
                      self.makeNewWindow(atOrigin: value.location)
                      #endif
                      self.dragging = true
                  }
              }
              .onEnded { value in
                  Log.d("onEnded value \(value)")
                  self.dragging = false
              }
          )
    }

    #if os(macOS)
    fileprivate func makeNewWindow(atOrigin origin: CGPoint) {
        let newClient = self.client.copy()

        newClient.trackFetcher = TrackFetcher(withServer: self.client.serverConnection)
        newClient.trackFetcher.audioPlayer.player = self.trackFetcher.audioPlayer.player
        newClient.trackFetcher.tracks = self.trackFetcher.tracks
        newClient.trackFetcher.desiredArtist = self.trackFetcher.desiredArtist
        newClient.trackFetcher.desiredAlbum = self.trackFetcher.desiredAlbum

        if let artist = newClient.trackFetcher.desiredArtist {
            if let album = newClient.trackFetcher.desiredAlbum {
                newClient.trackFetcher.trackTitle = "\(artist) \(album) songs"
            } else {
                newClient.trackFetcher.trackTitle = "\(artist) singles"
            }
        } else {
            newClient.trackFetcher.trackTitle = "FIX THIS!"
        }

        newClient.trackFetcher.refreshTracks()
        newClient.trackFetcher.refreshQueue()
        
        let contentView = TrackList(newClient)
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

