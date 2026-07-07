import SwiftUI

// A track's SHA1, draggable via the SwiftUI-native Transferable API instead of
// hand-building an NSItemProvider. Shared by every drag source in the client
// (BoundPanels/TrackList, on both macOS and iOS).
public struct TrackDragItem: Transferable {
    public let sha1: String

    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.sha1)
    }
}
