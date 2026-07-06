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
import AppKit

struct PanelWindowRoot: View {
    @ObservedObject var model: PanelWindowModel
    @ObservedObject var browser: ServerBrowser
    let controller: PanelWindowController
    let makeView: @MainActor (Panel, Client) -> AnyView

    @State private var browseClient: Client?

    var body: some View {
        VStack(spacing: 0) {
            DJHeaderBar()
                .contentShape(Rectangle())
                .help("Drag onto another window to combine them")
                // Drag the DJukebox header onto another window to merge this whole
                // window's panels into it.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { _ in
                            let session = controller.dragSession
                            if !session.isDragging { session.beginWindow(sourceWindow: model.id) }
                            session.update(screenPoint: NSEvent.mouseLocation)
                        }
                        .onEnded { _ in
                            controller.dragSession.end(screenPoint: NSEvent.mouseLocation)
                        }
                )
                // Small vacuum-tube VU meter tucked into the trailing end of the top
                // bar. Bound to the connected (shared) client's monitor, so every
                // window's bar shows the same live levels; non-interactive so it
                // doesn't intercept the header's window-merge drag.
                .overlay(alignment: .trailing) {
                    if let monitor = browser.currentClient?.levelMonitor {
                        VacuumTubeMeter(monitor: monitor, scale: 0.5)
                            .padding(.trailing, 14)
                            .allowsHitTesting(false)
                    }
                }
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
    /// fresh TrackFetcher so its artist/album/track selection is independent.
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
