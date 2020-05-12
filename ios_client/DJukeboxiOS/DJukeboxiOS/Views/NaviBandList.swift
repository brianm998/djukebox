import SwiftUI
import DJukeboxClient

public struct NaviBandList: View {
    @ObservedObject var trackFetcher: TrackFetcher
    var client: Client
    
    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
        self.client = client
    }

    public var body: some View {
        VStack {
            List(trackFetcher.bands) { (band: AudioTrack) in
                NavigationLink( destination: NaviAlbumList(self.client,
                                                           bands: self.trackFetcher.albums(forBand: band.Band),
                                                           title: band.Band))
                {
                    Text(band.Band)
                }
            }
        }
    }
}

