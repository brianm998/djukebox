//
//  ContentView.swift
//  DJukeboxiOS
//
//  Created by Brian Martin on 5/7/20.
//  Copyright © 2020 Brian Martin. All rights reserved.
//

import SwiftUI
import Combine
import DJukeboxClient

struct ContentView: View {
    @ObservedObject var browser: ServerBrowser
    @State private var showScan = false
    @State private var showSplash = true

    init(_ browser: ServerBrowser) { self.browser = browser }

    var body: some View {
        Group {
            // Once we've connected (to a real server) or fallen back to local,
            // there's a client to drive the UI. Before that, show the search status.
            if let client = browser.currentClient {
                tabs(client)
            } else {
                ServerConnectionView(browser) { client in tabs(client) }
            }
        }
        .modifier(ScanPresentation(browser: browser, isPresented: $showScan))
        // Fill the screen so the splash overlay's geometry — and the icon's
        // centered position — stay put when the underlying UI swaps in (e.g.
        // ServerConnectionView → the tab view once a client is ready). Without
        // this the overlay tracks the content's size and the icon slides.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(DJTheme.textPrimary)
        .tint(DJTheme.accent)
        .djScreenBackground()
        .preferredColorScheme(.dark)
        // Brief branded splash over everything at launch, then a cross-fade to
        // the UI (which shows the "Looking for DJukebox…" status if still connecting).
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

    private func tabs(_ client: Client) -> some View {
        // PairingApprovalHost surfaces incoming pair requests from other devices so
        // they can be allowed/denied here (no-op when running offline/local).
        PairingApprovalHost(server: client.serverConnection) {
            // iPad shows the app-icon badge as branding in the top-left corner;
            // iPhone doesn't (its screen is too small to spend the space).
            //
            // NOTE: on iPadOS 26 the TabView floats its tab selector at the top-
            // *center*. The branding must therefore be a small, non-interactive
            // corner overlay — an earlier full-width safeAreaInset bar (opaque,
            // spanning the top) sat right on top of the selector and made the tabs
            // vanish. Keeping the TabView as the plain root (no wrapping VStack) also
            // avoids iPadOS 26 rendering a second, duplicate tab bar.
            if layoutIsLarge() {
                tabView(client)
                    .overlay(alignment: .topLeading) {
                        DJIconBadge(size: 30)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                    }
            } else {
                tabView(client)
            }
        }
        .id(client.serverConnection.url)
    }

    private func tabView(_ client: Client) -> some View {
        // The vacuum-tube VU meter lives in the *background of each tab page*,
        // centered at the top and glowing up through the page's translucent panel
        // (macOS pins it in a corner instead). It has to be per-page rather than a
        // single layer behind the whole TabView: on iOS the TabView's page backdrop
        // is opaque, so anything behind the TabView (or the screen gradient itself)
        // never shows — the meter must sit inside the page, in front of that backdrop
        // but behind the semi-transparent djCard / nav bar. (An earlier attempt that
        // hung a .background on the TabView also jammed up iPad tab switching, since
        // the TabView bridges to a UITabBarController.)
        TabView {
            Group {
                if layoutIsLarge() {
                    ArtistAlbumTrackList(client) // looks ok on iPad, even mini
                        .djCard()
                        .padding(8)
                        .tubeBackdrop(client.levelMonitor)
                } else {
                    // iPhone browses via a navigation stack; its bars are themed
                    // globally (see AppDelegate) so it sits on the neon gradient.
                    // The tube backdrop goes *inside* the NavigationView (on the
                    // list content) — a background behind the NavigationView itself
                    // is hidden by its opaque UIKit backdrop, same as the TabView.
                    NavigationView {
                        NaviArtistList(client)
                            .tubeBackdrop(client.levelMonitor)
                            .navigationBarTitle("Artists", displayMode: .inline)
                    }
                }
            }
            .tabItem {
                Image(systemName: "list.dash")
                Text("tracks")
            }

            PlayingTracksView(client, onScan: startScan, onGoOffline: browser.rememberCurrentPlayLocal)
              .djCard()
              .padding(8)
              .tubeBackdrop(client.levelMonitor)
              .tabItem {
                  Image(systemName: "music.note.list")
                  Text("playing")
              }

            SearchView(client)
              .djCard()
              .padding(8)
              .tubeBackdrop(client.levelMonitor)
              .tabItem {
                  Image(systemName: "magnifyingglass.circle.fill")
                  Text("search")
              }

            HistoryView(client)
              .djCard()
              .padding(8)
              .tubeBackdrop(client.levelMonitor)
              .tabItem {
                  Image(systemName: "gobackward")
                  Text("history")
              }
        }
    }

    // kick off a fresh search and bring up the full-screen scan window
    private func startScan() {
        browser.start()
        showScan = true
    }
}

// Presents the scan window full screen on iOS 14+, falling back to a sheet on 13.x.
struct ScanPresentation: ViewModifier {
    @ObservedObject var browser: ServerBrowser
    @Binding var isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            ServerScanView(browser: browser, isPresented: $isPresented)
        }
    }
}

// Full-screen scan status shown while looking for a server. It dismisses itself
// as soon as the browser settles (either it connected, or it fell back to local).
struct ServerScanView: View {
    @ObservedObject var browser: ServerBrowser
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("📡").font(.system(size: 52))

            Text("Looking for DJukebox…")
                .font(.title)
                .bold()

            Text(statusMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            busyIndicator

            Spacer()

            // proceed to offline mode when the user knows there's no server around
            Button("Offline Mode") {
                browser.goOffline()
                isPresented = false
            }
            .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(browser.$state) { newState in
            if case .connected = newState { isPresented = false }
        }
    }

    private var statusMessage: String {
        if case .connecting = browser.state {
            return "Found a DJukebox server, connecting to it."
        }
        return "Searching your WiFi network for a DJukebox server."
    }

    @ViewBuilder
    private var busyIndicator: some View {
        ProgressView()
    }
}


// Launch splash: the app artwork centered on black. The icon's own corners are
// black, so it reads as the artwork glowing on screen.
//
// The icon spans half the shorter *screen* edge (≈25% margin on each side of that
// edge). `.ignoresSafeArea()` makes the GeometryReader report the full screen, so
// the icon is centered on and sized to the whole screen — matching the LaunchScreen
// storyboard, which uses the same half-of-shortest-edge rule against its full view.
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

private extension View {
    /// Place the vacuum-tube VU meter in the background of a tab page, centered at
    /// the top and non-interactive, so it glows up through the page's translucent
    /// panel. Applied per-page (see the note in `tabView`) because the iOS TabView's
    /// page backdrop is opaque — a single meter behind the whole TabView never shows.
    /// Smaller on iPhone, where space is tighter, than on iPad.
    func tubeBackdrop(_ monitor: AudioLevelMonitor) -> some View {
        background(alignment: .top) {
            VacuumTubeMeter(monitor: monitor, scale: layoutIsLarge() ? 1.0 : 0.72)
                .padding(.top, layoutIsLarge() ? 10 : 8)
                .allowsHitTesting(false)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ServerBrowser())
    }
}
