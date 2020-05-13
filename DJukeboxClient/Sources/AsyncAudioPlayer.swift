import Foundation
import DJukeboxCommon

// this class takes an AudioPlayerType and makes it async with closures so the UI can use it
// a lot of this logic mirrors that in routes.swift on the server,
// so that clients can have their own local playing queue
public class AsyncAudioPlayer: AsyncAudioPlayerType {
    var player: AudioPlayerType
    let fetcher: TrackFetcher
    let history: HistoryFetcher

    public init(player: AudioPlayerType, fetcher: TrackFetcher, history: HistoryFetcher) {
        self.player = player
        self.fetcher = fetcher
        self.history = history
    }

    public var isPaused: Bool { return player.isPaused }

    public func playTrack(withHash hash: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        if let track = fetcher.trackMap[hash] {
            player.play(sha1Hash: hash)
            closure(track, nil)
        } else {
            closure(nil, nil)   // XXX should make error here
        }
    }
    
    public func playTracks(_ tracks: [AudioTrack], closure: @escaping (Bool, Error?) -> Void) {
        for track in tracks {
            player.play(sha1Hash: track.SHA1)
        }
        closure(true, nil)
    }
    
    public func stopPlayingTrack(withHash hash: String,
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
                Log.i("HOLY FUCK")
            }
        }
        return PlayingQueue(isPaused: player.isPaused,
                            tracks: trackQueue,
                            playingTrackDuration: player.playingTrackDuration,
                            playingTrackPosition: player.playingTrackPosition)
    }
    
    public func movePlayingTrack(withHash hash: String,
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
    
    public func listPlayingQueue(closure: @escaping (PlayingQueue?, Error?) -> Void) {
        closure(self.playingQueue, nil)
    }

    public func update(with runtimeState: RuntimeState) {
        player.isPaused = runtimeState.isPaused
        if let playingHash = runtimeState.playingTrack {
            player.play(sha1Hash: playingHash)
        }
        for hash in runtimeState.pendingTracks {
            player.play(sha1Hash: hash)
        }
    }
    
    public func playRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        let random = Int.random(in: 0..<fetcher.allTracks.count)
        let track = fetcher.allTracks[random]
        player.play(sha1Hash: track.SHA1)
        closure(track, nil)
    }
    
    public func playRandomTrack(forBand band: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        let tracks = fetcher.tracks(forBand: band)
        let track = tracks[Int.random(in: 0..<tracks.count)]
        player.play(sha1Hash: track.SHA1)
    }
    
    public func playNewRandomTrack(closure: @escaping (AudioTrack?, Error?) -> Void) {
        var randomTrack: AudioTrack?
        var max = 100
        while randomTrack == nil,
              max > 0
        {
            max -= 1
            let random = Int.random(in: 0..<fetcher.allTracks.count)
            let track = fetcher.allTracks[random]
            if !history.hasPlay(for: track.SHA1),
               !history.hasSkip(for: track.SHA1),
               !isInQueue(track.SHA1)
            {
                randomTrack = track
            }
        }
        if let randomTrack = randomTrack {
            player.play(sha1Hash: randomTrack.SHA1)
            closure(randomTrack, nil)
        } else {
            closure(nil, nil)   // XXX should pass an error here
        }
    }
    
    fileprivate func isInQueue(_ hash: String) -> Bool {
        if let playingTrack = player.playingTrack,
           playingTrack.SHA1 == hash
        {
            return true
        }

        for queueHash in player.trackQueue {
            if queueHash == hash { return true }
        }
        
        return false
    }

    public func playNewRandomTrack(forBand band: String, closure: @escaping (AudioTrack?, Error?) -> Void) {
        var randomTrack: AudioTrack?
        var max = 100
        let tracksForThisBand = fetcher.tracks(forBand: band)
        while randomTrack == nil,
              max > 0
        {
            max -= 1
            let track = tracksForThisBand[Int.random(in: 0..<tracksForThisBand.count)]
            if !history.hasPlay(for: track.SHA1),
               !history.hasSkip(for: track.SHA1),
               !isInQueue(track.SHA1)
            {
                randomTrack = track
            }
        }
        if let randomTrack = randomTrack {
            player.play(sha1Hash: randomTrack.SHA1)
            closure(randomTrack, nil)
        } else {
            closure(nil, nil)   // XXX should pass an error here
        }
    }
    
    public func stopAllTracks(closure: @escaping (Bool, Error?) -> Void) {
        player.clearQueue()
        player.skip()
        closure(true, nil)
    }
    
    public func pausePlaying(closure: @escaping (Bool, Error?) -> Void) {
        player.pause()
        closure(true, nil)
    }
    
    public func resumePlaying(closure: @escaping (Bool, Error?) -> Void) {
        player.resume()
        closure(true, nil)
    }
}
