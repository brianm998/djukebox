//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    var body: some View {
        VStack {
            ArtistAlbumTrackList(trackFetcher: trackFetcher,
                                 historyFetcher: historyFetcher,
                                 serverConnection: serverConnection,
                                 audioPlayer: audioPlayer)

            
            PlayingTracksView(trackFetcher: trackFetcher,
                              audioPlayer: audioPlayer)

            SearchView(trackFetcher: trackFetcher,
                       audioPlayer: audioPlayer)

            HistoryView(historyFetcher: historyFetcher,
                        trackFetcher: trackFetcher,
                        audioPlayer: audioPlayer)
            
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


// an async audio player that subclasses the ServerConnection to play tracks on the server
let previewServerAudioPlayer: AsyncAudioPlayerType = ServerAudioPlayer(toUrl: serverURL, withPassword: password)
// an observable view object for showing lots of track based info
let previewTrackFetcher = TrackFetcher(withServer: server)

// an observable view object for the playing queue
let previewViewAudioPlayer = ViewObservableAudioPlayer(player: previewServerAudioPlayer)

let previewHistoryFetcher = HistoryFetcher(withServer: server, trackFetcher: previewTrackFetcher)


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(trackFetcher: previewTrackFetcher,
                    historyFetcher: previewHistoryFetcher,
                    serverConnection: server,
                    audioPlayer: previewViewAudioPlayer)
    }
}
