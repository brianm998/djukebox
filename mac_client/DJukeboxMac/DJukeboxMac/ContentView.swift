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

    init(trackFetcher: TrackFetcher,
         historyFetcher: HistoryFetcher,
         serverConnection: ServerType) 
    {
        self.trackFetcher = trackFetcher
        self.historyFetcher = historyFetcher
        self.serverConnection = serverConnection
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


fileprivate let server: ServerType = ServerConnection(toUrl: serverURL, withPassword: password)

// an async audio player that subclasses the ServerConnection to play tracks on the server
fileprivate let previewServerAudioPlayer: AsyncAudioPlayerType = ServerAudioPlayer(toUrl: serverURL, withPassword: password)

// an observable view object for showing lots of track based info
fileprivate let previewTrackFetcher = TrackFetcher(withServer: server)

fileprivate let previewHistoryFetcher = HistoryFetcher(withServer: server, trackFetcher: previewTrackFetcher)

fileprivate var previewQueues: [QueueType: AsyncAudioPlayerType] = [:]

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        previewQueues[.remote] = previewServerAudioPlayer
        return try ContentView(trackFetcher: previewTrackFetcher,
                               historyFetcher: previewHistoryFetcher,
                               serverConnection: server/**/)
    }
}
