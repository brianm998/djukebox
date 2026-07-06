//
//  ContentView.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import SwiftUI
import DJukeboxClient

struct ContentView: View {
    @ObservedObject private var browser: ServerBrowser
    @State private var showSplash = true

    init(_ browser: ServerBrowser) { self.browser = browser }

    var body: some View {
        // Branding bar (app-icon badge + neon wordmark) stays pinned to the top-left,
        // above both the connection/search screen and the connected UI.
        VStack(spacing: 0) {
            DJHeaderBar()
            DJNeonDivider()
            ServerConnectionView(browser) { client in
                // PairingApprovalHost surfaces incoming pair requests from other devices
                // so they can be allowed/denied from here.
                PairingApprovalHost(server: client.serverConnection) {
                    // Each section is its own neon "jukebox panel" on the gradient.
                    VStack(spacing: 10) {
                        ArtistAlbumTrackList(client)
                            .djCard()
                        // onScan rescans the network (ServerConnectionView shows the search
                        // screen meanwhile); onGoOffline stashes the play-local choice so a
                        // later reconnect can restore it.
                        PlayingTracksView(client,
                                          onScan: { self.browser.start() },
                                          onGoOffline: self.browser.rememberCurrentPlayLocal)
                            .djCard()
                        SearchView(client)
                            .djCard()
                        HistoryView(client)
                            .djCard()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Vacuum-tube VU meter in the upper-right corner.
                    .overlay(alignment: .topTrailing) {
                        VacuumTubeMeter(monitor: client.levelMonitor, scale: 1.05)
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                            .allowsHitTesting(false)
                    }
                }
                .id(client.serverConnection.url)
            }
        }
        // Fill the window so the splash overlay's geometry — and the centered icon —
        // stay put when the underlying UI swaps in once a client is ready.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(DJTheme.textPrimary)
        .tint(DJTheme.accent)
        .djScreenBackground()
        .preferredColorScheme(.dark)
        // Brief branded splash over everything at launch, then a cross-fade to the UI.
        .overlay {
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}

// Launch splash: the app artwork centered on black. The icon's own corners are
// black, so it reads as the artwork glowing on screen. It spans half the shorter
// edge of the window, so it scales with the window instead of looking tiny.
struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.5
            ZStack {
                Color.black
                Image("SplashIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ServerBrowser(initialQueueType: .remote))
    }
}
