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
    }

    private func tabs(_ client: Client) -> some View {
        TabView {
            if layoutIsLarge() {
                ArtistAlbumTrackList(client) // looks ok on iPad, even mini
                  .tabItem {
                      Image(systemName: "list.dash")
                      Text("tracks")
                  }
            } else {
                NavigationView {
                    NaviBandList(client)
                      .navigationBarTitle("Bands", displayMode: .inline)
                }
                  .tabItem {
                      Image(systemName: "list.dash")
                      Text("tracks")
                  }
            }

            PlayingTracksView(client, onScan: startScan, onGoOffline: browser.rememberCurrentPlayLocal)
              .tabItem {
                  Image(systemName: "music.note.list")
                  Text("playing")
              }

            SearchView(client)
              .tabItem {
                  Image(systemName: "magnifyingglass.circle.fill")
                  Text("search")
              }

            HistoryView(client)
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


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(ServerBrowser(password: password))
    }
}
