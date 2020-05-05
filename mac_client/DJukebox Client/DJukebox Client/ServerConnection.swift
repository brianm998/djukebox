import Cocoa
import SwiftUI
import CryptoKit
import DJukeboxCommon

protocol ServerType {
    func listTracks(closure: @escaping ([AudioTrack]?, Error?) -> Void)

    func listHistory(closure: @escaping (PlayingHistory?, Error?) -> Void)
    func listHistory(since: Int, closure: @escaping (PlayingHistory?, Error?) -> Void)
}

protocol AsyncAudioPlayerType {
    var isPaused: Bool { get }

    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func playTracks(_ tracks: [AudioTrack], closure: @escaping (Bool, Error?) -> Void)
    func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int/*? = nil*/,
                          closure: @escaping (Bool, Error?) -> Void)
    func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int,
                          closure: @escaping (PlayingQueue?, Error?) -> Void)
    func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void)
    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func playRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func playNewRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void)
    func playNewRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void)
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void)
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void)
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void)
}

class AsyncAudioPlayer: AsyncAudioPlayerType {
    let player: AudioPlayerType
    let fetcher: TrackFetcher

    init(player: AudioPlayerType, fetcher: TrackFetcher) {
        self.player = player
        self.fetcher = fetcher
        print("FUCK THIS")
    }

    var isPaused: Bool {
        return !player.isPlaying
    }

    func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        if let track = fetcher.trackMap[hash] {
            player.play(sha1Hash: hash)
            closure(track, nil)
        } else {
            closure(nil, nil)   // XXX should make error here
        }
    }
    
    func playTracks(_ tracks: [AudioTrack], closure: @escaping (Bool, Error?) -> Void) {
        for track in tracks {
            player.play(sha1Hash: track.SHA1)
        }
        closure(true, nil)
    }
    
    func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int,
                          closure: @escaping (Bool, Error?) -> Void) {
        player.stopPlaying(sha1Hash: hash, atIndex: index)
        closure(true, nil)
    }

    fileprivate var playingQueue: PlayingQueue {
        var trackQueue: [AudioTrack] = []
        if let playingTrack = player.playingTrack as? AudioTrack {
            trackQueue.append(playingTrack)
        }
        for queueHash in player.trackQueue {
            if let queueTrack = fetcher.trackMap[queueHash] {
                trackQueue.append(queueTrack)
            } else {
                print("HOLY FUCK")
            }
        }
        return PlayingQueue(tracks: trackQueue,
                            playingTrackDuration: player.playingTrackDuration,
                            playingTrackPosition: player.playingTrackPosition)
    }
    
    func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int,
                          closure: @escaping (PlayingQueue?, Error?) -> Void) {
        if let track = fetcher.trackMap[hash],
           player.move(track: track, fromIndex: fromIndex, toIndex: toIndex)
        {
            closure(self.playingQueue, nil)
        } else {
            closure(nil, nil)   // XXX should pass an error here 
        }
    }
    
    func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void) {
        print("listPlayingQueue")
        closure(self.playingQueue, nil)
    }
    
    func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        let random = Int.random(in: 0..<fetcher.allTracks.count)
        let track = fetcher.allTracks[random]
        player.play(sha1Hash: track.SHA1)
        closure(track, nil)
    }
    
    func playRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        // XXX implement this
    }
    
    func playNewRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        // XXX implement this
    }
    
    func playNewRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        // XXX implement this
    }
    
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) {
        // XXX implement this
    }
    
    func pausePlaying(closure: @escaping (Bool, Error?) -> Void) {
        player.pause()
        closure(true, nil)
    }
    
    func resumePlaying(closure: @escaping (Bool, Error?) -> Void) {
        player.resume()
        closure(true, nil)
    }
}

class ServerAudioPlayer: ServerConnection, AsyncAudioPlayerType {
    
    // XXX should query server on startup, in case it's already paused (need new api for that)
    var isPaused = false

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

    func playTracks(_ tracks: [AudioTrack], closure: @escaping (Bool, Error?) -> Void) {
        if tracks.count == 0 {
            closure(false, nil)
        } else if tracks.count > 0 {
            self.playTrack(withHash: tracks[0].SHA1) { track, error in
                if let track = track {
                    closure(true, nil)
                } else {
                    closure(false, error)
                }
            }
            var rest = tracks
            rest.removeFirst()
            playTracks(rest, closure: closure)
        }
    }
    
    func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int,
                          closure: @escaping (Bool, Error?) -> Void)
    {
        //if let index = index {
            self.request(path: "stop/\(hash)/\(index)", closure: closure)
    //} else {
      //      self.request(path: "stop/\(hash)", closure: closure)
        //}
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

    func playRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "rand/\(artist)", closure: closure)
    }
    
    func playNewRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "newrand", closure: closure)
    }
    
    func playNewRandomTrack(forArtist artist: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        self.requestJson(atPath: "newrand/\(artist)", closure: closure)
    }
    
    func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "stop", closure: closure)
    }

    func pausePlaying(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "pause") { success, error in
            if success { self.isPaused = true }
            closure(success, error)
        }
    }

    func resumePlaying(closure: @escaping (Bool, Error?) -> Void) {
        self.request(path: "resume") { success, error in
            if success { self.isPaused = false }
            closure(success, error)
        }
    }
}

class ViewObservableAudioPlayer: ObservableObject {
    let player: AsyncAudioPlayerType

    public init(player: AsyncAudioPlayerType) {
        self.player = player
    }
    
    var isPaused: Bool { return player.isPaused }
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

    fileprivate func request(path: String, closure: @escaping (Bool, Error?) -> Void) {
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

    fileprivate func requestJson<T>(atPath path: String, closure: @escaping (T?, Error?) -> Void) where T: Decodable {
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

