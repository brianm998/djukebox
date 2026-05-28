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

//let serverURL = "http://192.168.1.164:8080"
let serverURL = "http://192.168.5.254:8080"
//let serverURL = "http://192.168.4.22:8080"
//let serverURL = "http://127.0.0.1:8080"
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

        let client = Client(serverURL: serverURL,
                            password: password,
                            initialQueueType: .remote)
        let contentView = ContentView(client)

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
               let player = client.trackFetcher.audioPlayer.player
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


