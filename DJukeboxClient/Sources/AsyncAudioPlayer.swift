import Foundation
import DJukeboxCommon

// this class takes an AudioPlayerType and makes it async so the UI can use it
// a lot of this logic mirrors that in routes.swift on the server,
// so that clients can have their own local playing queue
//
// ---------------------------------------------------------------------------
// Client concurrency model (Swift 6):
// The client's playback/catalog/networking core is one callback graph bridged by
// non-isolated DJukeboxCommon protocols (AudioPlayerType, TrackFinderType,
// HistoryWriterType) that the server also implements — so those types can't be
// @MainActor; they stay `@unchecked Sendable`, serialized by the underlying
// AVFoundation/AVQueuePlayer. AsyncAudioPlayerType, however, is a CLIENT-ONLY
// protocol (not shared with the server), so it and this class are @MainActor
// (F30) — it wraps a non-isolated `player` but reads TrackFetcher (also
// @MainActor, F30) directly. The genuinely standalone UI state machines
// (ServerBrowser, PairingClient, PairingMonitor) are @MainActor too.
// ---------------------------------------------------------------------------
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

    public var playingTrackPosition: TimeInterval {
        return player.playingTrackPosition ?? 0
    }

    public func playTrack(withHash hash: String) async throws -> AudioTrack {
        guard let track = fetcher.trackMap[hash] else {
            throw AudioPlayerError.trackNotFound
        }
        player.play(sha1Hash: hash)
        // tapping a track is an explicit request to hear it: make sure playback
        // starts even if the player was restored in a paused state (otherwise the
        // track just sits in the queue with no sound / no progress).
        player.resume()
        return track
    }

    public func playTracks(_ tracks: [AudioTrack]) async throws -> Bool {
        for track in tracks {
            player.play(sha1Hash: track.SHA1)
        }
        player.resume()   // explicit play request: start even if restored paused
        return true
    }

    public func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int) async throws -> Bool {
        player.stopPlaying(sha1Hash: hash, atIndex: index)
        return true
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
                                 toIndex: Int) async throws -> PlayingQueue {
        guard let track = fetcher.trackMap[hash],
              player.move(track: track, fromIndex: fromIndex, toIndex: toIndex)
        else {
            throw AudioPlayerError.moveFailed
        }
        return self.playingQueue
    }

    public func listPlayingQueue() async throws -> PlayingQueue {
        return self.playingQueue
    }

    public func update(with runtimeState: RuntimeState) {
        player.isPaused = runtimeState.isPaused
        Log.i("runtimeState.playingTrackPosition \(runtimeState.playingTrackPosition)")
        player.playingTrackPosition = runtimeState.playingTrackPosition

        if let playingHash = runtimeState.playingTrack {
            player.play(sha1Hash: playingHash)
        }
        for hash in runtimeState.pendingTracks {
            player.play(sha1Hash: hash)
        }
    }

    public func playRandomTrack() async throws -> AudioTrack {
        guard fetcher.allTracks.count > 0 else {
            throw AudioPlayerError.noTrackAvailable
        }
        let random = Int.random(in: 0..<fetcher.allTracks.count)
        let track = fetcher.allTracks[random]
        player.play(sha1Hash: track.SHA1)
        return track
    }

    public func playRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        let tracks = fetcher.tracks(forArtist: artist)
        guard tracks.count > 0 else {
            throw AudioPlayerError.noTrackAvailable
        }
        let track = tracks[Int.random(in: 0..<tracks.count)]
        player.play(sha1Hash: track.SHA1)
        return track
    }

    public func playNewRandomTrack() async throws -> AudioTrack {
        var randomTrack: AudioTrack?
        var max = 100
        while randomTrack == nil,
              max > 0
        {
            max -= 1
            let random = Int.random(in: 0..<fetcher.allTracks.count)
            let track = fetcher.allTracks[random]
            if !(await history.hasPlay(for: track.SHA1)),
               !(await history.hasSkip(for: track.SHA1)),
               !isInQueue(track.SHA1)
            {
                randomTrack = track
            }
        }
        guard let randomTrack else {
            throw AudioPlayerError.noTrackAvailable
        }
        player.play(sha1Hash: randomTrack.SHA1)
        return randomTrack
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

    public func playNewRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        var randomTrack: AudioTrack?
        var max = 100
        let tracksForThisArtist = fetcher.tracks(forArtist: artist)
        while randomTrack == nil,
              max > 0
        {
            max -= 1
            let track = tracksForThisArtist[Int.random(in: 0..<tracksForThisArtist.count)]
            if !(await history.hasPlay(for: track.SHA1)),
               !(await history.hasSkip(for: track.SHA1)),
               !isInQueue(track.SHA1)
            {
                randomTrack = track
            }
        }
        guard let randomTrack else {
            throw AudioPlayerError.noTrackAvailable
        }
        player.play(sha1Hash: randomTrack.SHA1)
        return randomTrack
    }

    public func clearPlayingQueue() async throws -> Bool {
        player.clearQueue()
        return true
    }

    public func pausePlaying() async throws -> Bool {
        player.pause()
        return true
    }

    public func resumePlaying() async throws -> Bool {
        player.resume()
        return true
    }

    public func shuffleQueue() {
        player.shuffleQueue()
    }

    // local queue: audition the gain on the underlying local player's tap
    public func setLivePlaybackGain(decibels: Double) {
        player.setLivePlaybackGain(decibels: decibels)
    }

    public func playUntil(date: Date) async throws -> PlayingQueue {
        let now = Date()
        guard date > now else {
            return self.playingQueue
        }

        let secondsUntilTarget = date.timeIntervalSince(now)

        var queuedDuration: TimeInterval = 0
        if let playingTrack = player.playingTrack {
            let trackDuration = player.playingTrackDuration ?? playingTrack.timeInterval ?? 0
            let position = player.playingTrackPosition ?? 0
            queuedDuration += max(0, trackDuration - position)
        }
        for hash in player.trackQueue {
            if let track = fetcher.trackMap[hash] {
                queuedDuration += track.timeInterval ?? 0
            }
        }

        var timeToFill = secondsUntilTarget - queuedDuration
        guard timeToFill > 0 else {
            return self.playingQueue
        }

        let candidates = fetcher.allTracks.shuffled()
        for track in candidates {
            guard timeToFill > 0 else { break }
            if let duration = track.timeInterval,
               duration > 0,
               duration <= timeToFill,
               !isInQueue(track.SHA1)
            {
                player.play(sha1Hash: track.SHA1)
                timeToFill -= duration
            }
        }

        return self.playingQueue
    }
}
