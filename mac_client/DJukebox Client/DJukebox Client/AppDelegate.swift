//
//  AppDelegate.swift
//  DJukebox Client
//
//  Created by Brian Martin on 4/17/20.
//

import Cocoa
import SwiftUI
import CryptoKit

// XXX copied from the server
public struct AudioTrack: Decodable/*, ObservedObject<AudioTrack>*/ {
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
    func skipCurrentTrack(closure: @escaping (Bool, Error?) -> Void)
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) 
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void)
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void)
    func trackInfo(forHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) 
    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void)
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

    func skipCurrentTrack(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "skip", closure: closure)
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
var globalSillyString = "start"

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView(/*currentTrack: nil*/)
        
        /*
        server.listTracks() { audioTracks, error in
            if let audioTracks = audioTracks {
                print("got \(audioTracks.count) audio tracks")
                print("audioTracks[0] \(audioTracks[0])")
            } else {
                print("no tracks :(")
            }

            server.playRandomTrack() { audioTrack, error in
                if let error = error {
                    print("DOH")
                } else {
                    print("enqueued: \(audioTrack)")
                    server.listPlayingQueue() { audioTracks, error in
                        print("queue: \(audioTracks)")
                    }
                }
            }
        }*/

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

