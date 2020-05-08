//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
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
        VStack {
            ArtistAlbumTrackList(trackFetcher: trackFetcher,
                                 historyFetcher: historyFetcher,
                                 serverConnection: serverConnection)

            
            PlayingTracksView(trackFetcher: trackFetcher)

            SearchView(trackFetcher: trackFetcher)

            HistoryView(historyFetcher: historyFetcher, trackFetcher: trackFetcher)
            
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

fileprivate let previewClient = Client(serverURL: serverURL, password: password)

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(previewClient)
    }
}
