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

// The server is now discovered on the local network via mDNS / Bonjour
// (see ServerBrowser), so there's no hardcoded server address here anymore.
let password = "foobar"

var theWindow: NSWindow!

@NSApplicationMain
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

        let browser = ServerBrowser(password: password, initialQueueType: .remote)
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


