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
            // PairingApprovalHost surfaces incoming pair requests from other devices
            // so they can be allowed/denied from here.
            PairingApprovalHost(server: client.serverConnection) {
                VStack {
                    ArtistAlbumTrackList(client)
                    // onScan rescans the network (ServerConnectionView shows the search
                    // screen meanwhile); onGoOffline stashes the play-local choice so a
                    // later reconnect can restore it.
                    PlayingTracksView(client,
                                      onScan: { self.browser.start() },
                                      onGoOffline: self.browser.rememberCurrentPlayLocal)
                    SearchView(client)
                    HistoryView(client)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .id(client.serverConnection.url)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ServerBrowser(initialQueueType: .remote))
    }
}
