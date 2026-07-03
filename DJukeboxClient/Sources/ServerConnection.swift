import Foundation
import SwiftUI
import DJukeboxCommon

public protocol ServerType {
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void)

    func listHistory(closure: @escaping (PlayingHistory?, Error?) -> Void)
    func listHistory(since: Int, closure: @escaping (PlayingHistory?, Error?) -> Void)
    func post(history: ServerHistoryEntry, closure: @escaping (Bool, Error?) -> Void)

    // persist / read the per-track/album/artist playback gains the server applies
    func setVolumeAdjustment(_ adjustment: VolumeAdjustment, closure: @escaping (Bool, Error?) -> Void)
    func clearVolumeAdjustment(_ adjustment: VolumeAdjustment, closure: @escaping (Bool, Error?) -> Void)
    func listVolumeAdjustments(closure: @escaping ([VolumeAdjustment]?, Error?) -> Void)
    // the saved gain (dB) for a track, for pre-filling the volume control
    func savedGain(forHash hash: String, closure: @escaping (Double?, Error?) -> Void)

    // the global master gain (dB, <= 0), applied on top of every per-track gain
    func masterGain(closure: @escaping (Double?, Error?) -> Void)
    func setMasterGain(_ decibels: Double, closure: @escaping (Bool, Error?) -> Void)

    var authHeaderValue: String { get }
    var url: String { get }
}

public struct ServerHistoryEntry: Codable {
    public let hash: String
    public let time: Int
    public let fullyPlayed: Bool
}

// Mirrors the server's VolumeAdjustment wire type. Only the fields relevant to
// `scope` are set: track -> sha1, album -> artist + album, artist -> artist.
public struct VolumeAdjustment: Codable {
    public let scope: String
    public let sha1: String?
    public let artist: String?
    public let album: String?
    public let decibels: Double

    public init(scope: String, sha1: String? = nil, artist: String? = nil,
                album: String? = nil, decibels: Double) {
        self.scope = scope
        self.sha1 = sha1
        self.artist = artist
        self.album = album
        self.decibels = decibels
    }
}

// Mirrors the server's MasterVolume wire type: the single global gain (dB, <= 0).
public struct MasterVolume: Codable {
    public let decibels: Double
    public init(decibels: Double) { self.decibels = decibels }
}

// @unchecked Sendable: stored state is immutable (serverUrl / authHeaderValue are
// `let`); networking is stateless URLSession work. Subclasses (ServerAudioPlayer)
// add their own synchronization. See the client concurrency note in AsyncAudioPlayer.
public class ServerConnection: ObservableObject, ServerType, @unchecked Sendable {
    
    let serverUrl: String
    public let authHeaderValue: String

    public var url: String { return serverUrl }
    
    // The bearer token IS the credential now (no client-side hashing). For a
    // loopback connection on the same machine as the daemon, the server trusts the
    // peer regardless of the token, so a placeholder like "local" is fine and keeps
    // the streaming path (/stream/<token>/<sha1>) well-formed.
    public init(toUrl url: String, withToken token: String) {
        self.serverUrl = url
        self.authHeaderValue = token
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

    public func post(history: ServerHistoryEntry, closure: @escaping (Bool, Error?) -> Void) {
        let encoder = JSONEncoder()
        do {
            let jsonString = try encoder.encode(history)
            self.post(body: jsonString, toPath: "history", closure: closure)
        } catch {
            Log.e("json error \(error)")
        }
    }
    
    public func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void) {
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

    public func listHistory(closure: @escaping (PlayingHistory?, Error?) -> Void) {
        self.requestJson(atPath: "history", closure: closure)
    }

    public func listHistory(since: Int, closure: @escaping (PlayingHistory?, Error?) -> Void) {
        self.requestJson(atPath: "history/\(since)", closure: closure)
    }

    public func setVolumeAdjustment(_ adjustment: VolumeAdjustment,
                                    closure: @escaping (Bool, Error?) -> Void) {
        do {
            let body = try JSONEncoder().encode(adjustment)
            self.post(body: body, toPath: "volume", closure: closure)
        } catch {
            closure(false, error)
        }
    }

    public func clearVolumeAdjustment(_ adjustment: VolumeAdjustment,
                                      closure: @escaping (Bool, Error?) -> Void) {
        do {
            let body = try JSONEncoder().encode(adjustment)
            self.post(body: body, toPath: "volume/clear", closure: closure)
        } catch {
            closure(false, error)
        }
    }

    public func listVolumeAdjustments(closure: @escaping ([VolumeAdjustment]?, Error?) -> Void) {
        self.requestJson(atPath: "volume", closure: closure)
    }

    public func savedGain(forHash hash: String, closure: @escaping (Double?, Error?) -> Void) {
        self.requestJson(atPath: "volume/for/\(hash)") { (adj: VolumeAdjustment?, error: Error?) in
            closure(adj?.decibels, error)
        }
    }

    public func masterGain(closure: @escaping (Double?, Error?) -> Void) {
        self.requestJson(atPath: "volume/master") { (mv: MasterVolume?, error: Error?) in
            closure(mv?.decibels, error)
        }
    }

    public func setMasterGain(_ decibels: Double, closure: @escaping (Bool, Error?) -> Void) {
        do {
            let body = try JSONEncoder().encode(MasterVolume(decibels: decibels))
            self.post(body: body, toPath: "volume/master", closure: closure)
        } catch {
            closure(false, error)
        }
    }
}

