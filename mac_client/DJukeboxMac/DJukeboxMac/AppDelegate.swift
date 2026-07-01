//
//  AppDelegate.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import Cocoa
import SwiftUI
import CryptoKit
import DJukeboxCommon
import DJukeboxClient

// The server is discovered on the local network via mDNS / Bonjour (see
// ServerBrowser), and there's no shared password anymore: a daemon on this same
// machine is reached over loopback (trusted, no pairing), and a server on the
// WiFi requires this device to pair (see PairingClient / PairingStore).

// @MainActor: window handle only ever touched from the main-actor app lifecycle.
@MainActor var theWindow: NSWindow!

// @main replaces the deprecated @NSApplicationMain (an error under Swift 6);
// NSApplicationDelegate supplies the synthesized entry point.
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {

#if DEBUG
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .info),
            .file   : FileLogHandler(at: .error),
//          .alert  : AlertLogHandler(at: .warn),
          ]
#else
        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .warn),
          ]
#endif

        // Try a daemon on this machine (127.0.0.1) first — it's trusted over
        // loopback and needs no pairing. If there isn't one, browse the WiFi and
        // pair as needed. Default to playing locally, and quietly drop into
        // local-only mode (cached tracks) when no server is found.
        let browser = ServerBrowser(initialQueueType: .local,
                                    autoFallbackToLocal: true,
                                    tryLoopbackFirst: true)
        browser.start()
        let contentView = ContentView(browser)

        // Create the window and set the content view. 
        window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
          backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)

        theWindow = window
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keypress in
            guard self.window.firstResponder == self.window else {
                return keypress
            }
            if keypress.characters == " ",
               let player = browser.currentClient?.trackFetcher.audioPlayer.player
            {
                if player.isPaused {
                    player.resumePlaying() { success, error in
                        
                    }
                } else {
                    player.pausePlaying() { success, error in
                        
                    }
                }
                return nil
            } else {
                return keypress
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}


