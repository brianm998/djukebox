import Foundation

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
