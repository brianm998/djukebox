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
        VStack(spacing: 8) {
            TextField("search here", text: $searchQuery)
                .textFieldStyle(.plain)
                .djField()
                .padding([.horizontal, .top])

            List(trackFetcher.bands(matching: self.searchQuery)) { (band: AudioTrack) in
                NavigationLink(destination: NaviAlbumList(self.client,
                                                          band: band.Band,
                                                          title: band.Band))
                {
                    Text(band.Band).foregroundColor(DJTheme.textPrimary)
                }
            }
            .djListChrome()
        }
    }
}

