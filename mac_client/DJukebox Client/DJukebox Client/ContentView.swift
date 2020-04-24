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
                server.playTrack(withHash: self.audioTrack.SHA1) { track, error in
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
            List { 
                ForEach(trackFetcher.searchResults, id: \.self) { result in
                    SearchListCell(trackFetcher: self.trackFetcher, audioTrack: result)                    
                }
            }
        }
    }
}

struct ArtistAlbumTrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher

    var body: some View {
        HStack {
            VStack {
                Text("Artists")
                List(trackFetcher.artists) { artist in
                    Text(artist.Artist)
                      .onTapGesture {
                          self.trackFetcher.showAlbums(forArtist: artist.Artist)
                      }
                }
            }
            VStack {
                Text(trackFetcher.albumTitle)
                List(trackFetcher.albums) { artist in
                    Text(artist.Album ?? "Singles") // XXX constant
                      .foregroundColor(artist.Album == nil ? Color.red : Color.black)
                      .onTapGesture {
                          self.trackFetcher.showTracks(for: artist)
                      }
                }
            }
            VStack {
                Text(trackFetcher.trackTitle)
                List(trackFetcher.tracks) { artist in
                    Text(artist.TrackNumber == nil ? artist.Title : "\(artist.TrackNumber!) - \(artist.Title)")
                      .onTapGesture {
                          server.playTrack(withHash: artist.SHA1) { track, error in
                              self.trackFetcher.refreshQueue()
                              print("track \(track) error \(error)")
                          }
                      }
                }
            }
        }
    }
}

struct TrackDetail: View {
    @ObservedObject var track: AudioTrack
    @ObservedObject var trackFetcher: TrackFetcher
    
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
            if track.Duration != nil {
                Text(track.Duration!)
            }
        }
    }
    
    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }
}

struct PlayingQueue: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        List {
            ForEach(trackFetcher.playingQueue, id: \.self) { track in
                TrackDetail(track: track, trackFetcher: self.trackFetcher)
            }.onDelete(perform: delete)
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
        TrackDetail(track: track, trackFetcher: self.trackFetcher)
//        Text("\(track.Artist) \(track.Title)")
    }
}

struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    var body: some View {
        VStack {
            Spacer()
            ArtistAlbumTrackList(trackFetcher: trackFetcher)
            HStack {
                Spacer()
                ButtonStack(serverConnection: serverConnection)
                VStack(alignment: .leading) {
                    HStack {
                        Button(action: {
                            server.stopPlayingTrack(withHash: self.trackFetcher.currentTrack?.SHA1 ?? "") { audioTrack, error in
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

                        Button(action: {
                            if server.isPaused {
                                server.resumePlaying() { audioTrack, error in
                                    if let error = error {
                                        print("DOH")
                                    } else {
                                        print("enqueued: \(audioTrack)")
                                    }
                                }
                            } else {
                                server.pausePlaying() { audioTrack, error in
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
                        
                        
                        if trackFetcher.currentTrack == nil {
                            Text("Nothing Playing").foregroundColor(Color.gray)
                        } else {
                            CurrentTrackView(track: trackFetcher.currentTrack!,
                                             trackFetcher: trackFetcher)
                        }
                    }
                      .disabled(trackFetcher.currentTrack == nil)

                    PlayingQueue(trackFetcher: trackFetcher)
                }
            }
            SearchList(trackFetcher: trackFetcher)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(trackFetcher: trackFetcher, serverConnection: server)
    }
}
