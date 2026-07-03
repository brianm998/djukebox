//
//  PanelWindowRoot.swift
//  DJukeboxClient
//
//  SwiftUI root hosted in each workspace NSWindow: the branding bar + connection
//  gate, then the window's panel layout. Each window derives its own browse
//  Client (independent selection) while playback panels use the shared connected
//  client.
//

#if os(macOS)
import SwiftUI

struct PanelWindowRoot: View {
    @ObservedObject var model: PanelWindowModel
    @ObservedObject var browser: ServerBrowser
    let controller: PanelWindowController
    let makeView: @MainActor (PanelKind, Client) -> AnyView

    @State private var browseClient: Client?

    var body: some View {
        VStack(spacing: 0) {
            DJHeaderBar()
            DJNeonDivider()
            ServerConnectionView(browser) { sharedClient in
                connectedBody(sharedClient)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(DJTheme.textPrimary)
        .tint(DJTheme.accent)
        .djScreenBackground()
        .preferredColorScheme(.dark)
        .environment(\.panelController, controller)
        .environmentObject(controller.dragSession)
        // Rebuild this window's browse client if the server connection changes.
        .onChange(of: browser.currentClient?.serverConnection.url) { _ in
            browseClient = nil
        }
    }

    @ViewBuilder
    private func connectedBody(_ sharedClient: Client) -> some View {
        if let browse = browseClient {
            ZStack {
                LayoutView(root: model.root,
                           context: PanelContext(windowID: model.id,
                                                 browseClient: browse,
                                                 sharedClient: sharedClient,
                                                 makeView: makeView)) { newRoot in
                    model.root = newRoot
                    controller.persist()
                }
                DropIndicatorOverlay(windowID: model.id)
            }
        } else {
            Color.clear.onAppear { buildBrowseClient(from: sharedClient) }
        }
    }

    /// This window's own browse client: a copy sharing the audio player, with a
    /// fresh TrackFetcher so its band/album/track selection is independent.
    private func buildBrowseClient(from shared: Client) {
        let client = shared.copy()
        client.trackFetcher = TrackFetcher(withServer: shared.serverConnection)
        client.trackFetcher.audioPlayer.player = shared.trackFetcher.audioPlayer.player
        model.seed?(client.trackFetcher)
        client.trackFetcher.refreshTracks()
        client.trackFetcher.refreshQueue()
        browseClient = client
    }
}
#endif
