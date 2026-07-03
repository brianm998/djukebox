import SwiftUI

public struct ArtistAlbumTrackList: View {
    private var client: Client

    public init(_ client: Client) { self.client = client }

    public var body: some View {
        HStack(spacing: 0) {
            BandList(client)
            DJNeonVDivider()
            AlbumList(client)
            DJNeonVDivider()
            TrackList(client)
        }
    }
}

