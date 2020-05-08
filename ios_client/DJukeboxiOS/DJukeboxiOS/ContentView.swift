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

    init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.historyFetcher = client.historyFetcher
        self.serverConnection = client.server
    }

    var body: some View {
        TabView {
            ArtistAlbumTrackList(trackFetcher: trackFetcher,
                                 historyFetcher: historyFetcher,
                                 serverConnection: serverConnection)
              .tabItem { Text("tracks") }

            PlayingTracksView(trackFetcher: trackFetcher)
              .tabItem { Text("queue") }

            SearchView(trackFetcher: trackFetcher)
              .tabItem { Text("search") }

            HistoryView(historyFetcher: historyFetcher,
                        trackFetcher: trackFetcher)
              .tabItem { Text("history") }
        }
    }
}


fileprivate let previewClient = Client(serverURL: serverURL, password: password)

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(previewClient)
    }
}

