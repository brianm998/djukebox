//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI
import DJukeboxClient

struct ContentView: View {
    private var client: Client

    init(_ client: Client) { self.client = client }

    var body: some View {
        VStack {
            ArtistAlbumTrackList(client)
            
            PlayingTracksView(trackFetcher: client.trackFetcher)

            SearchView(trackFetcher: client.trackFetcher)

            HistoryView(client)
            
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

fileprivate let previewClient = Client(serverURL: serverURL, password: password)

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(previewClient)
    }
}
