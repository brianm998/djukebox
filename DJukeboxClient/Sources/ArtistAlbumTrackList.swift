import SwiftUI

public struct ArtistAlbumTrackList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var historyFetcher: HistoryFetcher
    var serverConnection: ServerType

    public init(trackFetcher: TrackFetcher,
                historyFetcher: HistoryFetcher,
                serverConnection: ServerType)
    {
        self.trackFetcher = trackFetcher
        self.historyFetcher = historyFetcher
        self.serverConnection = serverConnection
    }

    public var body: some View {
        HStack {
            ArtistList(trackFetcher: trackFetcher)
            AlbumList(trackFetcher: trackFetcher,
                      serverConnection: serverConnection)
            TrackList(trackFetcher: trackFetcher,
                      historyFetcher: historyFetcher,
                      serverConnection: serverConnection)
        }
    }
}

