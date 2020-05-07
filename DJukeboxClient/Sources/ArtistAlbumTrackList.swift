import SwiftUI

public struct ArtistAlbumTrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    public init(trackFetcher: TrackFetcher,
                historyFetcher: HistoryFetcher,
                serverConnection: ServerType,
                audioPlayer: ViewObservableAudioPlayer)
    {
        self.trackFetcher = trackFetcher
        self.historyFetcher = historyFetcher
        self.serverConnection = serverConnection
        self.audioPlayer = audioPlayer
    }

    public var body: some View {
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

