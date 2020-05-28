import SwiftUI
import DJukeboxCommon

#if os(macOS)

// XXX should split this out into two separate mac and iOS files

struct TrackList: View {
    var client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var dragging = false
    
    @State private var showingActionSheet = false
//    @State private var showAllTracksToast: Bool = false
    
    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }
    
    var body: some View {
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
                      self.makeNewWindow(atOrigin: value.location)
                      self.dragging = true
                  }
              }
              .onEnded { value in
                  Log.d("onEnded value \(value)")
                  self.dragging = false
              }
          )
        /*
          .toast(isPresented: $showAllTracksToast) {
              Text("All tracks playing")
          }
          */


        
    }

    fileprivate func makeNewWindow(atOrigin origin: CGPoint) {
        let newClient = self.client.copy()

        newClient.trackFetcher = TrackFetcher(withServer: self.client.serverConnection)
        newClient.trackFetcher.audioPlayer.player = self.trackFetcher.audioPlayer.player
        newClient.trackFetcher.tracks = self.trackFetcher.tracks
        newClient.trackFetcher.desiredBand = self.trackFetcher.desiredBand
        newClient.trackFetcher.desiredAlbum = self.trackFetcher.desiredAlbum

        if let band = newClient.trackFetcher.desiredBand {
            if let album = newClient.trackFetcher.desiredAlbum {
                newClient.trackFetcher.trackTitle = "\(band) \(album) songs"
            } else {
                newClient.trackFetcher.trackTitle = "\(band) singles"
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
}

// this is only here to avoid an autorelease crash upon release of sub-windows
fileprivate var windows: [NSWindow] = [] 


#else
// XXX MIDDLE



struct TrackList: View {
    var client: Client
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var dragging = false
    
    @State private var showingActionSheet = false
//    @State private var showAllTracksToast: Bool = false
    
    public init(_ client: Client) {
        self.client = client
        self.trackFetcher = client.trackFetcher
    }
    
    var body: some View {
        return VStack {
            Spacer()
            HStack() {
                Text(trackFetcher.trackTitle)
                if self.trackFetcher.tracks.count > 0 {

                    Button(action: {self.showingActionSheet = true }) {
                        Image(systemName: "plus").imageScale(.large)
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
          .actionSheet(isPresented: $showingActionSheet) {
              ActionSheet(title: Text(""),
                          buttons: [
                            .default(Text("Play All")) {
                                self.client.trackFetcher.audioPlayer.player?.playTracks(self.trackFetcher.tracks.sorted()) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                    withAnimation { /*self.showAllTracksToast = true*/ }
                                }
                            },
                            .default(Text("Cache All")) {
                                self.client.trackFetcher.cache(tracks: self.trackFetcher.tracks)
                            },
                            .cancel()
                          ])
          }
        /*
          .toast(isPresented: $showAllTracksToast) {
              Text("All tracks playing")
          }
          */


        
    }

}

#endif
