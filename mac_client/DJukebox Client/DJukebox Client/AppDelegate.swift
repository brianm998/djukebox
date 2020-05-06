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

// the server connection for tracks and history 
let server: ServerType = ServerConnection(toUrl: serverURL, withPassword: password)


// this is used for writing locally played tracks to the history on the server
public class ServerHistoryWriter: HistoryWriterType {
    public func writePlay(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: true)
        server.post(history: history) { success, error in
            print("wrote play of \(sha1)")
        }
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        let history = ServerHistoryEntry(hash: sha1,
                                         time: Int(date.timeIntervalSince1970),
                                         fullyPlayed: false)
        server.post(history: history) { success, error in
            print("wrote skip of \(sha1)")
        }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.

        // an async audio player that subclasses the ServerConnection to play tracks on the server
        let serverAudioPlayer: AsyncAudioPlayerType = ServerAudioPlayer(toUrl: serverURL, withPassword: password)
        
        // an observable view object for showing lots of track based info
        let trackFetcher = TrackFetcher(withServer: server/*, audioPlayer: audioPlayerToUse*/)

        // an observable object for keeping the history up to date from the server
        let historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)
        
        // this monstrosity plays the files locally via streaming urls
        let localAudioPlayer =
          AsyncAudioPlayer(player: NetworkAudioPlayer(trackFinder: TrackFinder(trackFetcher: trackFetcher,
                                                                               serverConnection: server),
                                                      historyWriter: ServerHistoryWriter()),
                           fetcher: trackFetcher,
                           history: historyFetcher)

        // we can play either locally or on the server
        var audioPlayerToUse: AsyncAudioPlayerType = localAudioPlayer

        var shouldPlayLocally = false
        
        if !shouldPlayLocally { // play on server ?
            audioPlayerToUse = serverAudioPlayer
        }

        trackFetcher.audioPlayer = audioPlayerToUse
        
        // an observable view object for the playing queue
        let viewAudioPlayer = ViewObservableAudioPlayer(player: audioPlayerToUse)

        historyFetcher.refresh()
        
        let contentView = ContentView(trackFetcher: trackFetcher,
                                      historyFetcher: historyFetcher,
                                      serverConnection: server,
                                      audioPlayer: viewAudioPlayer)
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

