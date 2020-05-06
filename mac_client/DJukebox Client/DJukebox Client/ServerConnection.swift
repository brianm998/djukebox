import Cocoa
import SwiftUI
import CryptoKit
import DJukeboxCommon

protocol ServerType {
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void)

    func listHistory(closure: @escaping (PlayingHistory?, Error?) -> Void)
    func listHistory(since: Int, closure: @escaping (PlayingHistory?, Error?) -> Void)
    func post(history: ServerHistoryEntry, closure: @escaping (Bool, Error?) -> Void)
}

public struct ServerHistoryEntry: Codable {
    public let hash: String
    public let time: Int
    public let fullyPlayed: Bool
}

class ServerConnection: ObservableObject, ServerType {
    
    let serverUrl: String
    let authHeaderValue: String
    
    init(toUrl url: String, withPassword password: String) {
        self.serverUrl = url
        self.authHeaderValue =
          SHA512.hash(data: Data(password.utf8)).map {
              String(format: "%02hhx", $0)
          }.joined()
    }

    internal func request(path: String, closure: @escaping (Bool, Error?) -> Void) {
        if let url = URL(string: "\(serverUrl)/\(path)") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
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

    internal func post(body: Data, toPath path: String, closure: @escaping (Bool, Error?) -> Void) {
        if let url = URL(string: "\(serverUrl)/\(path)") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")

            request.timeoutInterval = 60.0
            request.httpBody = body
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

    internal func requestJson<T>(atPath path: String, closure: @escaping (T?, Error?) -> Void) where T: Decodable {
        let urlPath = path.replacingOccurrences(of: " ", with: "%20")
        if let url = URL(string: "\(serverUrl)/\(urlPath)") {
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

    func post(history: ServerHistoryEntry, closure: @escaping (Bool, Error?) -> Void) {
        let encoder = JSONEncoder()
        do {
            let jsonString = try encoder.encode(history)
            self.post(body: jsonString, toPath: "history", closure: closure)
        } catch {
            print("json error \(error)")
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

    func listHistory(closure: @escaping (PlayingHistory?, Error?) -> Void) {
        self.requestJson(atPath: "history", closure: closure)
    }

    func listHistory(since: Int, closure: @escaping (PlayingHistory?, Error?) -> Void) {
        self.requestJson(atPath: "history/\(since)", closure: closure)
    }
}

