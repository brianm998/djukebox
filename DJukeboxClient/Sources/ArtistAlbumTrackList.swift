import SwiftUI

public struct ArtistAlbumTrackList: View {
    private var client: Client

    public init(_ client: Client) { self.client = client }

    public var body: some View {
        HStack {
            ArtistList(client)
            AlbumList(client)
            TrackList(client)
        }
    }
}

