import Cocoa
import SwiftUI
import CryptoKit

protocol ServerType {
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void)
    func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void)
    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) 
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void)
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void)
    func trackInfo(forHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) 
    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func stopPlayingTrack(withHash hash: String, closure: @escaping (Bool, Error?) -> Void)
    func movePlayingTrack(withHash hash: String, fromIndex: Int, toIndex: Int,
                          closure: @escaping (PlayingQueue?, Error?) -> Void)
    var isPaused: Bool { get }
}

class ServerConnection: ObservableObject, ServerType {
    
    let serverUrl: String
    let authHeaderValue: String

    // XXX should query server on startup, in case it's already paused
    fileprivate var local_isPaused: Bool = false
    
    var isPaused: Bool {
        print("server isPaused \(local_isPaused)")
        return local_isPaused
    }
    
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

    func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int,
                          closure: @escaping (PlayingQueue?, Error?) -> Void)
    {
        self.requestJson(atPath: "move/\(hash)/\(fromIndex)/\(toIndex)") { (playingQueue: PlayingQueue?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let playingQueue = playingQueue {
                closure(playingQueue, nil)
            } else {
                closure(nil, nil) // XXX ???
            }
        }
    }
        
    func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void) {
        self.requestJson(atPath: "queue") { (playingQueue: PlayingQueue?, error: Error?) in
            if let error = error {
                closure(nil, error)
            } else if let playingQueue = playingQueue {
                closure(playingQueue, nil)
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
        self.request(path: "pause") { success, error in
            if success { self.local_isPaused = true }
            closure(success, error)
        }
    }

    func resumePlaying(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "resume") { success, error in
            if success { self.local_isPaused = false }
            closure(success, error)
        }
    }
}

