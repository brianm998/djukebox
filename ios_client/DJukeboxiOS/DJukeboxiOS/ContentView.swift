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
                  .tabItem {
                      Image(systemName: "list.dash")
                      Text("tracks")
                  }
            } else {
                NavigationView {
                    NaviBandList(client)
                      .navigationBarTitle("Bands", displayMode: .inline)
                }
                  .tabItem {
                      Image(systemName: "list.dash")
                      Text("tracks")
                  }
            }

            PlayingTracksView(client)
              .tabItem {
                  Image(systemName: "music.note.list")
                  Text("playing")
              }

            SearchView(client)
              .tabItem {
                  Image(systemName: "magnifyingglass.circle.fill")
                  Text("search")
              }

            HistoryView(client)
              .tabItem {
                  Image(systemName: "gobackward")
                  Text("history")
              }
        }
    }
}


fileprivate let previewClient = Client(serverURL: serverURL, password: password)

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(previewClient)
    }
}

