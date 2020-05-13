import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviBandList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var client: Client
    @State private var searchQuery: String = "" 
    
    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.client = client
    }

    public var body: some View {
        VStack {
            TextField(
              "search here",
              text: $searchQuery,
              onCommit: { Log.d(self.searchQuery) }
            )
            Spacer()
            
            List(trackFetcher.bands(matching: self.searchQuery)) { (band: AudioTrack) in
                NavigationLink(destination: NaviAlbumList(self.client,
                                                          bands: self.trackFetcher.albums(forBand: band.Band),
                                                          title: band.Band))
                {
                    Text(band.Band)
                }
            }
        }
    }
}

