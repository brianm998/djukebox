//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI

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
            List(trackFetcher.searchResults) { result in
                Text("\(result.Artist) - \(result.Album ?? "") - \(result.Title)")
                  .onTapGesture {
                      server.playTrack(withHash: result.SHA1) { track, error in
                          self.trackFetcher.refreshQueue()
                          print("track \(track) error \(error)")
                      }
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


struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var serverConnection: ServerConnection //ServerType

    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                ButtonStack(serverConnection: serverConnection)
                List {
                    ForEach(trackFetcher.playingQueue, id: \.self) { track in
                        HStack(alignment: .center) {
                            Button(action: {
                                self.trackFetcher.showAlbums(forArtist: track.Artist)
                            }) {
                                Text(track.Artist)
                            }
                            if self.hasAlbum(track) {
                                Button(action: {
                                    self.trackFetcher.showTracks(for: track)
                                }) {
                                    Text(track.Album!)
                                }
                            }
                            Text(track.Title)
                            if track.Duration != nil {
                                Text(track.Duration!)
                            }
                        }
                    }.onDelete(perform: delete)
                }
            }
            SearchList(trackFetcher: trackFetcher)
            ArtistAlbumTrackList(trackFetcher: trackFetcher)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func delete (at offsets: IndexSet) {
        print("delete @ \(offsets)")

        offsets.forEach { index in
            print("index \(index)")
            trackFetcher.removeItemFromPlayingQueue(at: index)
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(trackFetcher: trackFetcher, serverConnection: server)
    }
}
