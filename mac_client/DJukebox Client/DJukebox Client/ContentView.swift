//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var fetcher: QueueFetcher
    
    var body: some View {
        HStack {
            VStack {
                Button(action: {
                           server.playRandomTrack() { audioTrack, error in
                               if let error = error {
                                   print("DOH")
                               } else if let audioTrack = audioTrack {
                                   print("enqueued: \(audioTrack)")
                                   globalSillyString = "\(audioTrack.Artist): \(audioTrack.Title)"
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
            List(fetcher.tracks) { track in
                HStack(alignment: .center) {
                    Text(track.Artist)
                    Text(track.Title)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(fetcher: fetcher)/*currentTrack: AudioTrack(Artist: "foo",
                                             Album: "me",
                                             Title: "me",
                                             Filename: "me",
                                             SHA1: "me",
                                             Duration: "me",
                                             AudioBitrate: "me",
                                             SampleRate: "me",
                                             TrackNumber: "me",
                                             Genre: "me",
                                             OriginalDate: "never"))
*/
    }
}
