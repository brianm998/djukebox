//
//  AppDelegate.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import Cocoa
import SwiftUI
import CryptoKit

public class TrackFetcher: ObservableObject {
    var allTracks: [AudioTrack] = []

    @Published var artists: [AudioTrack] = []
    @Published var albums: [AudioTrack] = []
    @Published var tracks: [AudioTrack] = []

    @Published var albumTitle: String
    @Published var trackTitle: String
    
    @Published var playingQueue: [AudioTrack] = []

    let server: ServerType
    
    init(withServer server: ServerType) {
        self.server = server
        self.albumTitle = "Albums"
        self.trackTitle = "Songs"
        refreshTracks()
        refreshQueue()
    }

    func refreshTracks() {
        server.listTracks() { tracks, error in
            if let tracks = tracks {
                var artistMap: [String:AudioTrack] = [:]
                for track in tracks {
                    if track.Album == nil {
                        print("artist \(track.Artist) has orphaned tracks")
                    }
                    artistMap[track.Artist] = track
                }
                DispatchQueue.main.async {
                    self.allTracks = tracks
                    self.artists = Array(artistMap.values).sorted()
                }
            }
        }
    }

    func removeItemFromPlayingQueue(at index: Int) {
        guard index >= 0 else { return }
        guard index < playingQueue.count else { return }

        server.stopPlayingTrack(withHash: playingQueue[index].SHA1) { success, error in
            if success { self.refreshQueue() }
        }
    }
    
    func refreshQueue() {
        server.listPlayingQueue() { tracks, error in
            if let tracks = tracks {
                DispatchQueue.main.async {
                    self.playingQueue = tracks
                }
            }
        }
    }

    // show all tracks for the artist/album combo in the passed AudioTrack
    func showTracks(for audioTrack: AudioTrack) {
        var tracks: [AudioTrack] = []

        let desiredArtist = audioTrack.Artist
        let desiredAlbum = audioTrack.Album

        if let desiredAlbum = desiredAlbum {
            for track in allTracks {
                if track.Artist == desiredArtist,
                   track.Album == desiredAlbum
                {
                    tracks.append(track)
                }
            }
        } else {
            for track in allTracks {
                if track.Artist == desiredArtist,
                   track.Album == nil
                {
                    tracks.append(track)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.tracks = tracks.sorted()
            if let desiredAlbum = desiredAlbum {
                self.trackTitle = "\(desiredAlbum) songs"
            } else {
                self.trackTitle = "\(desiredArtist) songs"
            }
        }
    }
    
    func showAlbums(forArtist artist: String) {
        print("for artist \(artist)")
        var albums: [String] = []

        var albumMap: [String:AudioTrack] = [:]

        let singles = "Singles"
        
        for track in allTracks {
            if track.Artist == artist {
                if let album = track.Album {
                    albumMap[album] = track
                } else {
                    albumMap[singles] = track
                    print("missing album for track \(track.Artist) \(track.Title)")
                }
            }
        }
        DispatchQueue.main.async {
            self.albums = Array(albumMap.values).sorted()
            self.albumTitle = "\(artist) albums"
        }
    }
}

// XXX copied from the server
public class AudioTrack: Decodable, Identifiable, Comparable, Hashable {
    public static func < (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        if lhs.Artist == rhs.Artist {
            // dig in deeper
            if let lhsAlbum = lhs.Album,
               let rhsAlbum = rhs.Album
            {
                if lhsAlbum == rhsAlbum,
                   let lhsTrackNumberStr = lhs.TrackNumber,
                   let rhsTrackNumberStr = rhs.TrackNumber,
                   let lhsTrackNumber = Int(lhsTrackNumberStr),
                   let rhsTrackNumber = Int(rhsTrackNumberStr)
                {
                    return lhsTrackNumber < rhsTrackNumber
                } else {
                    return lhsAlbum < rhsAlbum
                }
            } else {
                return lhs.Title < rhs.Title
            }
        } else {
            return lhs.Artist < rhs.Artist
        }
    }
    
    public static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        return lhs.SHA1 == rhs.SHA1
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SHA1)
    }
    
    let Artist: String
    let Album: String?
    let Title: String
    let Filename: String
    let SHA1: String
    let Duration: String?
    let AudioBitrate: String?
    let SampleRate: String?
    let TrackNumber: String?
    let Genre: String?
    let OriginalDate: String?
}

protocol ServerType {
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void)
    func listPlayingQueue(closure: @escaping ([AudioTrack]?, Error?) -> Void)
    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) 
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void)
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void)
    func trackInfo(forHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) 
    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func stopPlayingTrack(withHash hash: String, closure: @escaping (Bool, Error?) -> Void)
}

class ServerConnection: ServerType {
    
    let serverUrl: String
    let authHeaderValue: String

    init(toUrl url: String, withPassword password: String) {
        self.serverUrl = url
        self.authHeaderValue =
          SHA512.hash(data: Data(password.utf8)).map {
              String(format: "%02hhx", $0)
          }.joined()
    }

    fileprivate func request(path: String, closure: @escaping (Bool, Error?) -> Void) {
        if let url = URL(string: "\(serverUrl)/\(path)") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authHeaderValue, forHTTPHeaderField:"Authorization")
            request.timeoutInterval = 60.0
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    closure(false, error)
                } else {
                    closure(true, nil)
                }
            }.resume()
        } else {
            closure(false, nil)
        }
    }

    fileprivate func requestJson<T>(atPath path: String, closure: @escaping (T?, Error?) -> Void) where T: Decodable {
        if let url = URL(string: "\(serverUrl)/\(path)") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authHeaderValue, forHTTPHeaderField:"Authorization")
            request.timeoutInterval = 60.0
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data {
                    do {
                        let json = try JSONDecoder().decode(T.self, from: data)
                        closure(json, nil)
                    } catch {
                        closure(nil, error)
                    }
                }
            }.resume()
        } else {
            closure(nil, nil)
        }
    }
    
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void) {
        self.requestJson(atPath: "tracks") { (audioTracks: [AudioTrack]?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let audioTracks = audioTracks {
                closure(audioTracks, nil)
            } else {
                closure(nil, nil) // XXX ???
            }
        }
    }

    func trackInfo(forHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "info/\(hash)") { (audioTrack: AudioTrack?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let audioTrack = audioTrack {
                closure(audioTrack, nil)
            } else {
                closure(nil, nil) // XXX ???
            }
        }
    }

    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "play/\(hash)") { (audioTrack: AudioTrack?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let audioTrack = audioTrack {
                closure(audioTrack, nil)
            } else {
                closure(nil, nil) // XXX ???
            }
        }
    }

    func stopPlayingTrack(withHash hash: String, closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "stop/\(hash)", closure: closure)
    }
    
    func listPlayingQueue(closure: @escaping ([AudioTrack]?, Error?) -> Void) {
        self.requestJson(atPath: "queue") { (audioTracks: [AudioTrack]?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let audioTracks = audioTracks {
                closure(audioTracks, nil)
            } else {
                closure(nil, nil) // XXX ???
            }
        }
    }

    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "rand", closure: closure)
    }
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "stop", closure: closure)
    }

    func pausePlaying(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "pause", closure: closure)
    }

    func resumePlaying(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "resume", closure: closure)
    }
}


let server: ServerType = ServerConnection(toUrl: "http://127.0.0.1:8080", withPassword: "foobar")
let trackFetcher = TrackFetcher(withServer: server)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView(trackFetcher: trackFetcher)
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

