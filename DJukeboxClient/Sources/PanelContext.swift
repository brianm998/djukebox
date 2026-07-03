//
//  PanelContext.swift
//  DJukeboxClient
//
//  What a rendered panel needs from its host window. Browse panels
//  (bands/albums/songs/search) use the window's OWN client so each window browses
//  independently; playback panels (controls/queue/history) use the SHARED client
//  (the connected one that carries the live refresh timer) so they reflect one
//  global playback state. `makeView` is injected by the app target so it can
//  compose app-target views (e.g. the mac control bar) with the library views.
//

#if os(macOS)
import SwiftUI

public struct PanelContext {
    /// The window this panel lives in (used for tear-out).
    public let windowID: UUID
    /// The window's own client — independent browse selection.
    public let browseClient: Client
    /// The global connected client — live playback / history.
    public let sharedClient: Client
    public let makeView: @MainActor (Panel, Client) -> AnyView

    public init(windowID: UUID,
                browseClient: Client,
                sharedClient: Client,
                makeView: @escaping @MainActor (Panel, Client) -> AnyView) {
        self.windowID = windowID
        self.browseClient = browseClient
        self.sharedClient = sharedClient
        self.makeView = makeView
    }

    /// Which client a given panel kind should bind to.
    public func client(for kind: PanelKind) -> Client {
        switch kind {
        case .bands, .albums, .songs, .allSearch:
            return browseClient
        case .playingControls, .playingList, .history:
            return sharedClient
        }
    }
}
#endif
