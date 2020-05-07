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

let serverURL = "http://127.0.0.1:8080"
let password = "foobar"

enum QueueType {
    case local
    case remote
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    // set this to .local to play locally instead of on the server
    let queueType: QueueType = .remote
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // the server connection for tracks and history 
        let server = ServerConnection(toUrl: serverURL, withPassword: password)

        // an observable view object for showing lots of track based info
        let trackFetcher = TrackFetcher(withServer: server)

        // an observable object for keeping the history up to date from the server
        let historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)

        // which queue do we play to?
        var audioPlayer: AsyncAudioPlayerType!

        switch queueType {
        case .local:
            /*
             this monstrosity plays the files locally via streaming urls on the server
             */
            let trackFinder = TrackFinder(trackFetcher: trackFetcher, serverConnection: server)
            let player = NetworkAudioPlayer(trackFinder: trackFinder,
                                            historyWriter: ServerHistoryWriter(server: server))
            audioPlayer = AsyncAudioPlayer(player: player, fetcher: trackFetcher, history: historyFetcher)

        case .remote:
            /*
             an audio player that subclasses the ServerConnection to use apis to manage a server queue
            */
            audioPlayer = ServerAudioPlayer(toUrl: serverURL, withPassword: password)
        }

        // set after init to avoid a circular dependency in the .local case above
        trackFetcher.audioPlayer = audioPlayer
        
        historyFetcher.refresh()
        
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView(trackFetcher: trackFetcher,
                                      historyFetcher: historyFetcher,
                                      serverConnection: server,
                                      audioPlayer: ViewObservableAudioPlayer(player: audioPlayer))
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            trackFetcher.refreshQueue()
            historyFetcher.refresh()
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

