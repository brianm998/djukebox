//
//  ContentView.swift
//  DJukeboxiOS
//
//  Created by Brian Martin on 5/7/20.
//  Copyright © 2020 Brian Martin. All rights reserved.
//

import SwiftUI
import DJukeboxClient

struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    var body: some View {
        TabView {
            ArtistAlbumTrackList(trackFetcher: trackFetcher,
                                 historyFetcher: historyFetcher,
                                 serverConnection: serverConnection,
                                 audioPlayer: audioPlayer)
              .tabItem { Text("tracks") }

            PlayingTracksView(trackFetcher: trackFetcher,
                              audioPlayer: audioPlayer)
              .tabItem { Text("queue") }

            SearchView(trackFetcher: trackFetcher,
                       audioPlayer: audioPlayer)
              .tabItem { Text("search") }

            HistoryView(historyFetcher: historyFetcher,
                        trackFetcher: trackFetcher,
                        audioPlayer: audioPlayer)
              .tabItem { Text("history") }
        }
    }
}


fileprivate let server: ServerType = ServerConnection(toUrl: serverURL, withPassword: password)

// an async audio player that subclasses the ServerConnection to play tracks on the server
fileprivate let previewServerAudioPlayer: AsyncAudioPlayerType = ServerAudioPlayer(toUrl: serverURL, withPassword: password)
// an observable view object for showing lots of track based info
fileprivate let previewTrackFetcher = TrackFetcher(withServer: server)

// an observable view object for the playing queue
fileprivate let previewViewAudioPlayer = ViewObservableAudioPlayer(player: previewServerAudioPlayer)

fileprivate let previewHistoryFetcher = HistoryFetcher(withServer: server, trackFetcher: previewTrackFetcher)

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(trackFetcher: previewTrackFetcher,
                    historyFetcher: previewHistoryFetcher,
                    serverConnection: server,
                    audioPlayer: previewViewAudioPlayer)
    }
}

