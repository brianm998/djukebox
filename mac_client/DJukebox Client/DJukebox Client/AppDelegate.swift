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
  
let server/*: ServerType*/ = ServerConnection(toUrl: serverURL, withPassword: password)
let serverAudioPlayer = ServerAudioPlayer(toUrl: serverURL, withPassword: password)

let trackFetcher = TrackFetcher(withServer: server, audioPlayer: serverAudioPlayer)
let audioPlayer = ViewObservableAudioPlayer(player: serverAudioPlayer)
let historyFetcher = HistoryFetcher(withServer: server)

public class TrackFinder: TrackFinderType {
    
    public var tracks: [String : (AudioTrackType, [URL])]
    
    let trackFetcher: TrackFetcher

    init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
        self.tracks = [:]
    }
    
    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let track = trackFetcher.trackMap[sha1Hash],
           let url = URL(string: "\(serverURL)/stream/sha1Hash") // XXX need auth still with URLRequest
        {
            return (track, url)
        }
        return nil
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
        if let track = trackFetcher.trackMap[sha1Hash] {
            return track
        }
        return nil
    }
}

let trackFinder = TrackFinder(trackFetcher: trackFetcher)

//AsyncAudioPlayer

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        historyFetcher.refresh()
        
        let contentView = ContentView(trackFetcher: trackFetcher,
                                      historyFetcher: historyFetcher,
                                      serverConnection: server,
                                      audioPlayer: audioPlayer)
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

