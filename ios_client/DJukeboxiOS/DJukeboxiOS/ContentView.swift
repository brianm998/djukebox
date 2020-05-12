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
            if layoutIsLarge() {
                ArtistAlbumTrackList(client) // looks ok on iPad, even mini
                  .tabItem { Text("tracks") }
            } else {
                NavigationView {
                    NaviBandList(client)
                      .navigationBarTitle("Bands", displayMode: .inline)
                }
                 .tabItem { Text("tracks") }
            }

            PlayingTracksView(client)
              .tabItem { Text("queue") }

            SearchView(client)
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

