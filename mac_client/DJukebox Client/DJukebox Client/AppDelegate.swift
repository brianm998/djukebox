//
//  AppDelegate.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import Cocoa
import SwiftUI
import CryptoKit

let server/*: ServerType*/ = ServerConnection(toUrl: "http://127.0.0.1:8080", withPassword: "foobar")
let trackFetcher = TrackFetcher(withServer: server)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView(trackFetcher: trackFetcher, serverConnection: server)
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            trackFetcher.refreshQueue()
        }

        // Create the window and set the content view. 
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

