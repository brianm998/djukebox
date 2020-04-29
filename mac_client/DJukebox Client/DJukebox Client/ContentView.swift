//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI

struct SearchListCell: View {

    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var audioTrack: AudioTrack
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    @State private var toggleIsOn = false
    
    var body: some View {
        HStack {
            /*
            Toggle("foo", isOn: self.$toggleIsOn)
              .layoutPriority(1.0)
              .frame(width: 80, height: 40)
            //.fixedSize()
              .background(Color.green)
            //.frame(minWidth: 300, minHeight: 300)
              .padding()
            Button(action: {
                       print("fuck this shit")
                   }) {
                Text("XXX").foregroundColor(Color.orange)
            }.frame(maxWidth: 80, maxHeight: 30).background(Color.blue)
            */
             Text("\(audioTrack.Artist) - \(audioTrack.Album ?? "") - \(audioTrack.Title)")
               .onTapGesture {
                   self.serverConnection.playTrack(withHash: self.audioTrack.SHA1) { track, error in
                       self.trackFetcher.refreshQueue()
                       print("track \(track) error \(error)")
                   }
             }
        }
    }
}

struct SearchList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var searchQuery: String = "" 
    @ObservedObject var serverConnection: ServerConnection //ServerType

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Search: ")
                TextField(
                    "search here",
                    text: $searchQuery,
                    onEditingChanged: { foo in print("edit cha\(foo) \(self.searchQuery)") },
                    onCommit: { self.trackFetcher.search(for: self.searchQuery) }
                )
                Spacer()
            }
            if trackFetcher.searchResults.count > 0 {
                List {
                    ForEach(trackFetcher.searchResults, id: \.self) { result in
                        SearchListCell(trackFetcher: self.trackFetcher,
                                       audioTrack: result,
                                       serverConnection: self.serverConnection)                    
                    }
                }
            }
        }
    }
}

struct ArtistList: View {
    @ObservedObject var trackFetcher: TrackFetcher

    var body: some View {
        VStack {
            Spacer()
            Text("Artists")
            List(trackFetcher.artists) { artist in
                Text(artist.Artist)
                  .onTapGesture {
                      self.trackFetcher.showAlbums(forArtist: artist.Artist)
                  }
               
            }
        }
    }
}

struct AlbumList: View {
    @ObservedObject var trackFetcher: TrackFetcher

    var body: some View {
        VStack {
            Spacer()
            Text(trackFetcher.albumTitle)
            List(trackFetcher.albums) { artist in
                Text(artist.Album ?? "Singles") // XXX constant
                  .foregroundColor(artist.Album == nil ? Color.red : Color.black)
                  .onTapGesture {
                      self.trackFetcher.showTracks(for: artist)
                  }
            }
        }
    }
}


struct TrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    @State private var dragging = false 
    
    var body: some View {
        VStack {
            Spacer()
            HStack() {
                Text(trackFetcher.trackTitle)
                Button(action: {
                    self.serverConnection.playTracks(self.trackFetcher.tracks) { success, error in
                        self.trackFetcher.refreshQueue()
                    }
                }) {
                    Text("Play All")
                }
                  //.alignmentGuide(.trailing, computeValue: { d in d[.trailing] } )
            }
            List(trackFetcher.tracks) { track in
                Text(track.TrackNumber == nil ? track.Title : "\(track.TrackNumber!) - \(track.Title) - \(track.timeIntervalString)")
                  .onTapGesture {
                      self.serverConnection.playTrack(withHash: track.SHA1) { track, error in
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
                      self.makeNewWindow(atOrigin: value.location)
                      self.dragging = true
                  }
              }
              .onEnded { value in
                  print("onEnded value \(value)")
                  self.dragging = false
              }
          )
    }

    fileprivate func makeNewWindow(atOrigin origin: CGPoint) {
        let trackFetcher = TrackFetcher(withServer: self.serverConnection)
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
        let contentView = TrackList(trackFetcher: trackFetcher, serverConnection: self.serverConnection)
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

struct ArtistAlbumTrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    var body: some View {
        HStack {
            ArtistList(trackFetcher: trackFetcher)
            AlbumList(trackFetcher: trackFetcher)
            TrackList(trackFetcher: trackFetcher, serverConnection: serverConnection)
        }
    }
}

struct TrackDetail: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher

    var showDuration = true
    
    var body: some View {
        HStack(alignment: .center) {
            Button(action: {
                       self.trackFetcher.showAlbums(forArtist: self.track.Artist)
                   }) {
                Text(track.Artist)
            }
            if self.hasAlbum(track) {
                Button(action: {
                           self.trackFetcher.showTracks(for: self.track)
                       }) {
                    Text(track.Album!)
                }
            }
            Text(track.Title)
            if showDuration && track.Duration != nil {
                Text(track.Duration!)
            }
        }
    }
    
    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }
}

struct ProgressBar: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().frame(width: geometry.size.width,
                                  height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(Color.gray)

                // XXX This sucks to have the track fetcher so deeply imbedded here
                Rectangle().frame(width: min(CGFloat(self.trackFetcher.playingTrackProgress ?? 0)*geometry.size.width,
                                             geometry.size.width),
                                  height: geometry.size.height)
                  .foregroundColor(Color.green)
                  .animation(.linear)

                if self.trackFetcher.totalDuration > 0 {
                    Text(self.remainingTimeText(self.trackFetcher.currentTrackRemainingTime))
                      .offset(x: 8)
                      .foregroundColor(Color.gray)
                      .opacity(0.7)
                }
            }.cornerRadius(8)
        }
    }

    private func remainingTimeText(_ amount: TimeInterval) -> String {
        if amount < 60 {
            return "\(Int(amount)) seconds left"
        } else {
            let duration = Int(amount)
            let seconds = String(format: "%02d", duration % 60)
            let minutes = duration / 60
            return "\(minutes):\(seconds) left"
        }
    }
}

struct PlayingQueueView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    var body: some View {
        List {
            ForEach(trackFetcher.playingQueue, id: \.self) { track in
                TrackDetail(track: track, trackFetcher: self.trackFetcher)
            }
              .onDelete(perform: delete)
              .onMove(perform: move)
              //.onInsert(of: ["public.url"], perform: drop) // XXX doesn't work
        }
    }
    private func drop(at index: Int, _ items: [NSItemProvider]) {
        for item in items {
            _ = item.loadObject(ofClass: URL.self) { url, error in
                print("url \(url) error \(error)")
                //DispatchQueue.main.async {
                    //url.map { self.links.insert($0, at: index) }
            //}
            }
        }
    }
    
    private func move(source: IndexSet, destination: Int) {
        let startIndex = source.sorted()[0]
        let endIndex = destination
        let trackToMove = trackFetcher.playingQueue[startIndex]
        if startIndex < endIndex {
            let positionsAhead = endIndex-startIndex-1
            print("moving track \(trackToMove.SHA1) up \(positionsAhead) positions from \(startIndex)")
            serverConnection.movePlayingTrack(withHash: trackToMove.SHA1,
                                              fromIndex: startIndex,
                                              toIndex: startIndex + positionsAhead) { playingQueue, error in
                if let queue = playingQueue {
                    self.trackFetcher.update(playingQueue: queue)
                }
            }
        } else if startIndex > endIndex {
            let positionsBehind = startIndex-endIndex
            print("moving track \(trackToMove.SHA1) down \(positionsBehind) positions from \(startIndex)")
            serverConnection.movePlayingTrack(withHash: trackToMove.SHA1,
                                              fromIndex: startIndex,
                                              toIndex: startIndex - positionsBehind) { playingQueue, error in
                if let queue = playingQueue {
                    self.trackFetcher.update(playingQueue: queue)
                }
            }
        } else {
            print("not moving at all")
        }
    }

    func delete (at offsets: IndexSet) {
        print("delete @ \(offsets)")

        offsets.forEach { index in
            print("index \(index)")
            trackFetcher.removeItemFromPlayingQueue(at: index)
        }
    }

}

struct CurrentTrackView: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher

    var body: some View {
        TrackDetail(track: track, trackFetcher: self.trackFetcher, showDuration: false)
        //        Text("\(track.Artist) \(track.Title)")
    }
}
struct MyDropDelegate: DropDelegate {
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [kUTTypePlainText as String])
    }
    
    func dropEntered(info: DropInfo) {
        print("dropEntered")
        //NSSound(named: "Morse")?.play()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        print("performDrop")
        //NSSound(named: "Submarine")?.play()
        
        //let gridPosition = getGridPosition(location: info.location)
        //self.active = gridPosition
        
        if let item = info.itemProviders(for: [kUTTypePlainText as String]).first {
            item.loadItem(forTypeIdentifier: kUTTypePlainText as String, options: nil) { (urlData, error) in
                //DispatchQueue.main.async {
                print("UrlData \(urlData)")
                    if let urlData = urlData as? String {
                        print("FUCK: \(urlData)")
                    } else {
                        print("FAILED1")
                    }
            //}
            }

            
            return true
            
        } else {
            print("FAILED")
            return false
        }
    }
}

struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    let dropDelegate = MyDropDelegate(/*imageUrls: $imageUrls, active: $active*/)
    
    var body: some View {
        
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                if trackFetcher.currentTrack == nil {
                    Text("Nothing Playing").foregroundColor(Color.gray)
                } else {
                    CurrentTrackView(track: trackFetcher.currentTrack!,
                                     trackFetcher: trackFetcher)
                      .layoutPriority(1.0)
                    ProgressBar(trackFetcher: trackFetcher)
                      .layoutPriority(0.1)
                      .frame(maxWidth: .infinity, maxHeight: 20)
                }
                Spacer()
            }
              .disabled(trackFetcher.currentTrack == nil)

            PlayingQueueView(trackFetcher: trackFetcher, serverConnection: serverConnection)

              .onDrop(of: [kUTTypePlainText as String], delegate: dropDelegate)
            /*
              .onDrop(of: [kUTTypePlainText as String], isTargeted: nil) { providers in
                  for provider in providers {
                      print("fuck \(provider.registeredTypeIdentifiers())")
                      if provider.hasItemConformingToTypeIdentifier(kUTTypePlainText as String) {
                          print("FUCK YES")
                          provider.loadItem(forTypeIdentifier: kUTTypePlainText as String) { item, error in
                              print("got item \(item) error \(error)")
                          }
                      } else {
                          print("FUCK NO")
                      }
                      
                      provider.loadObject(ofClass: String.self) { string,two  in
                          print("woot! \(string) \(two)")
                      }

                  }
                  return false
              }
*/
        }
    }
}


struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    var body: some View {
        VStack {
            ArtistAlbumTrackList(trackFetcher: trackFetcher,
                                 serverConnection: serverConnection)

            
            HStack {
                Spacer()
                ButtonStack(trackFetcher: trackFetcher, serverConnection: serverConnection)
                Spacer()
                PlayingTracksView(trackFetcher: trackFetcher, serverConnection: serverConnection)
            }

            
            SearchList(trackFetcher: trackFetcher,
                       serverConnection: serverConnection)

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(trackFetcher: trackFetcher, serverConnection: server)
    }
}
