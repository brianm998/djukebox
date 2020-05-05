import Foundation
import DJukeboxCommon

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
