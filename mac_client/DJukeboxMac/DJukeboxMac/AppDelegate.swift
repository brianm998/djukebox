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

let serverURL = "http://192.168.1.164:8080"
//let serverURL = "http://127.0.0.1:8080"
let password = "foobar"

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    var contentView: some View {
        // the server connection for tracks and history 
        let server = ServerConnection(toUrl: serverURL, withPassword: password)

        // an observable view object for showing lots of track based info
        let trackFetcher = TrackFetcher(withServer: server)

        // an observable object for keeping the history up to date from the server
        let historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)

        // which queue do we play to?
        var audioPlayer: AsyncAudioPlayerType!

        let trackFinder = TrackFinder(trackFetcher: trackFetcher,
                                      serverConnection: server)

        /*
         this monstrosity plays the files locally via streaming urls on the server
         */
        let player = NetworkAudioPlayer(trackFinder: trackFinder,
                                        historyWriter: ServerHistoryWriter(server: server))
        trackFetcher.add(queueType: .local,
                         withPlayer: AsyncAudioPlayer(player: player,
                                                      fetcher: trackFetcher,
                                                      history: historyFetcher))
        /*
         an audio player that subclasses the ServerConnection to use apis to manage a server queue
         */
        trackFetcher.add(queueType: .remote,
                         withPlayer: ServerAudioPlayer(toUrl: serverURL, withPassword: password))

        do {
            try trackFetcher.watch(queue: .remote)
        } catch {
            print("can't watch queue: \(error)")
        }
        
        // set after init to avoid a circular dependency in the .local case above
        //trackFetcher.audioPlayer = audioPlayer
        
        historyFetcher.refresh()
        trackFetcher.refreshTracks()
        trackFetcher.refreshQueue()
        
        // Create the SwiftUI view that provides the window contents.
        let contentView = try ContentView(trackFetcher: trackFetcher,
                                          historyFetcher: historyFetcher,
                                          serverConnection: server) 
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            trackFetcher.refreshQueue()
            historyFetcher.refresh()
        }

        return contentView
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the window and set the content view. 
        window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
          backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: self.contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

