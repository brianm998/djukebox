//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI
import DJukeboxClient

struct ContentView: View {
    @ObservedObject private var browser: ServerBrowser

    init(_ browser: ServerBrowser) { self.browser = browser }

    var body: some View {
        ServerConnectionView(browser) { client in
            VStack {
                ArtistAlbumTrackList(client)
                PlayingTracksView(client)
                SearchView(client)
                HistoryView(client)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ServerBrowser(password: password, initialQueueType: .remote))
    }
}
