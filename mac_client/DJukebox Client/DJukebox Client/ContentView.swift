//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI

struct ButtonStack: View {
    
    var body: some View {
        VStack {
            Button(action: {
                       server.playRandomTrack() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else if let audioTrack = audioTrack {
                               print("enqueued: \(audioTrack.Title)")
                           }
                           trackFetcher.refreshQueue()
                       }
                   }) {
                Text("Random")
            }
            Button(action: {
                       server.stopAllTracks() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                           trackFetcher.refreshQueue()
                       }
                   }) {
                Text("Stop")
            }
            Button(action: {
                       server.skipCurrentTrack() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                           trackFetcher.refreshQueue()
                       }
                   }) {
                Text("Skip")
            }
            Button(action: {
                       server.pausePlaying() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                       }
                   }) {
                Text("Pause")
            }
            Button(action: {
                       server.resumePlaying() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                       }
                   }) {
                Text("Resume")
            }
            Button(action: {
                trackFetcher.refreshTracks()
            }) {
                Text("Refresh")
            }
            Button(action: {
                trackFetcher.refreshQueue()
            }) {
                Text("Refresh Q")
            }
        }        
    }
}

struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    private func hasAlbum(_ track: AudioTrack) -> Bool {
        return track.Album != nil
    }

    var body: some View {
        VStack {
            HStack {
                ButtonStack()
                List {
                    ForEach(trackFetcher.playingQueue, id: \.self) { track in
                        HStack(alignment: .center) {
                            /*
                            Button(action: {
                                server.stopPlayingTrack(withHash: track.SHA1) { success, error in
                                    self.trackFetcher.refreshQueue()
                                    print("stopped playing \(track.SHA1)? \(success) error \(error)")
                                }
                            }) {
                                Text("X")
                            }
                            */
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
                          .onTapGesture {
                              self.trackFetcher.showTracks(for: artist)
                          }
                    }
                }
                VStack {
                    Text(trackFetcher.trackTitle)
                    List(trackFetcher.tracks) { artist in
                        Text(artist.Title)
                          .onTapGesture {
                              server.playTrack(withHash: artist.SHA1) { track, error in
                                self.trackFetcher.refreshQueue()
                                  print("track \(track) error \(error)")
                              }
                          }
                    }
                }
            }
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
        ContentView(trackFetcher: trackFetcher)
    }
}
