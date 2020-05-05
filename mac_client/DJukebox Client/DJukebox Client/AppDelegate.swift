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



public class HistoryWriter: HistoryWriterType {
    public func writePlay(of sha1: String, at date: Date) throws {
        print("write play of \(sha1)")
    }

    public func writeSkip(of sha1: String, at date: Date) throws {
        print("write skip of \(sha1)")
    }
}

public class TrackFinder: TrackFinderType {
    
    public var tracks: [String : (AudioTrackType, [URL])]
    
    let trackFetcher: TrackFetcher

    init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
        self.tracks = [:]
    }
    
    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let track = trackFetcher.trackMap[sha1Hash],
           let url = URL(string: "\(serverURL)/stream/\(sha1Hash)") // XXX need auth still with URLRequest
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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.

        // XXX XXX

        // an async audio player that subclasses the ServerConnection to play tracks on the server
        let serverAudioPlayer: AsyncAudioPlayerType = ServerAudioPlayer(toUrl: serverURL, withPassword: password)
        
        // an observable view object for showing lots of track based info
        let trackFetcher = TrackFetcher(withServer: server/*, audioPlayer: audioPlayerToUse*/)
        
        // XXX
        // XXX
        // XXX
        let fakeHistoryWriter = HistoryWriter()
        let trackFinder = TrackFinder(trackFetcher: trackFetcher)
        let macAudioPlayer: AudioPlayerType = NetworkAudioPlayer(trackFinder: trackFinder,
                                                                 historyWriter: fakeHistoryWriter)
        
        let localAudioPlayer = AsyncAudioPlayer(player: macAudioPlayer, fetcher: trackFetcher)
        // XXX
        // XXX
        // XXX

        var audioPlayerToUse: AsyncAudioPlayerType = localAudioPlayer
        if true {
            // play on server
            audioPlayerToUse = serverAudioPlayer
        }

        trackFetcher.audioPlayer = audioPlayerToUse
        
        // an observable view object for the playing queue
        let viewAudioPlayer = ViewObservableAudioPlayer(player: audioPlayerToUse)

        let historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)
        
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

