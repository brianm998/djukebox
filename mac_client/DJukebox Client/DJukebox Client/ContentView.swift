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
        }        
    }
}

struct ContentView: View {
    @ObservedObject var queueFetcher: QueueFetcher
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        VStack {
            HStack {
                ButtonStack()
                List(queueFetcher.tracks) { track in
                    HStack(alignment: .center) {
                        Text(track.Artist)
                        Text(track.Title)
                    }
                }
            }
            HStack {
                List(trackFetcher.artists) { artist in
                    Text(artist.Artist)
                      .onTapGesture {
                        self.trackFetcher.showAlbums(forArtist: artist.Artist)
                      }
                }
                List(trackFetcher.albums) { artist in
                    Text(artist.Album ?? "XXX")
                      .onTapGesture {
                          self.trackFetcher.showTracks(for: artist)
                      }
                }
                List(trackFetcher.tracks) { artist in
                    Text(artist.Title)
                      .onTapGesture {
                          server.playTrack(withHash: artist.SHA1) { track, error in
                              print("track \(track) error \(error)")
                          }
                      }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(queueFetcher: queueFetcher, trackFetcher: trackFetcher)
    }
}
