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
    var client: Client

    init(_ client: Client) { self.client = client }

    var body: some View {
        TabView {
            ArtistAlbumTrackList(client)
              .tabItem { Text("tracks") }

            PlayingTracksView(trackFetcher: client.trackFetcher)
              .tabItem { Text("queue") }

            SearchView(trackFetcher: client.trackFetcher)
              .tabItem { Text("search") }

            HistoryView(client)
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

