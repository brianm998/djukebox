//
//  DJukeboxApp.swift
//  DJukeboxiOS
//
//  Created by Brian Martin on 5/7/20.
//  Copyright © 2020 Brian Martin. All rights reserved.
//

import SwiftUI
import DJukeboxClient
import DJukeboxCommon

// The server is discovered on the local network via mDNS / Bonjour (see
// ServerBrowser). There's no shared password anymore: an iOS device always
// reaches the server over the WiFi, so it pairs with it (see PairingClient /
// PairingStore) and keeps a per-device token afterwards.

// SwiftUI App lifecycle entry point (replaces the old AppDelegate +
// SceneDelegate pair). AppDelegate still exists, wired in via
// @UIApplicationDelegateAdaptor, purely to keep the two pieces of real UIKit
// setup it does (audio session category, nav bar theming) — everything else
// that lived there was boilerplate stubs.
@main
struct DJukeboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Owned here (the App is now the top-level owner) instead of being handed
    // in from a SceneDelegate. On iOS, if no server turns up we quietly drop
    // into local-only mode rather than showing a failure screen.
    @StateObject private var browser = ServerBrowser(autoFallbackToLocal: true)

    var body: some Scene {
        WindowGroup {
            ContentView(browser)
                .task {
                    browser.start()
                }
        }
    }
}
