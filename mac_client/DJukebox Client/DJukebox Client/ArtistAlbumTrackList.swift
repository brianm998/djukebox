import SwiftUI


struct ArtistAlbumTrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    var body: some View {
        HStack {
            ArtistList(trackFetcher: trackFetcher)
            AlbumList(trackFetcher: trackFetcher,
                      serverConnection: serverConnection,
                      audioPlayer: audioPlayer)
            TrackList(trackFetcher: trackFetcher,
                      historyFetcher: historyFetcher,
                      serverConnection: serverConnection,
                      audioPlayer: audioPlayer)
        }
    }
}

