import Foundation
import DJukeboxCommon

// @unchecked Sendable: bridges the (non-isolated) AsyncAudioPlayerType to server
// endpoints. `isPaused`/`playingTrackPosition` are only touched from URLSession
// callbacks and the main thread; treated as internally main-thread-disciplined.
//
// ServerConnection's own request/post/requestJson helpers are still
// closure-based pending F07 (which will convert ServerType to async throws), so
// every method here bridges to them via withCheckedThrowingContinuation. This
// bridging is intentionally thin — it should mostly fall away once F07 lands.
public class ServerAudioPlayer: ServerConnection, AsyncAudioPlayerType, @unchecked Sendable {


    public var playingTrackPosition: TimeInterval = 0 // XXX

    public func update(with runtimeState: RuntimeState) {
        Log.w("unimplementd, should not be called")
    }


    // XXX should query server on startup, in case it's already paused (need new api for that)
    public var isPaused = false

    public func playTrack(withHash hash: String) async throws -> AudioTrack {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "play/\(hash)") { (audioTrack: AudioTrack?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioTrack = audioTrack {
                    continuation.resume(returning: audioTrack)
                } else {
                    continuation.resume(throwing: AudioPlayerError.trackNotFound)
                }
            }
        }
    }

    public func playTracks(_ tracks: [AudioTrack]) async throws -> Bool {
        guard tracks.count > 0 else { return false }
        // call the server's play/{hash} endpoint for every track, concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask {
                    _ = try await self.playTrack(withHash: track.SHA1)
                }
            }
            try await group.waitForAll()
        }
        return true
    }

    public func stopPlayingTrack(withHash hash: String,
                          atIndex index: Int) async throws -> Bool
    {
        try await withCheckedThrowingContinuation { continuation in
            self.request(path: "stop/\(hash)/\(index)") { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    public func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int) async throws -> PlayingQueue
    {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "move/\(hash)/\(fromIndex)/\(toIndex)") { (playingQueue: PlayingQueue?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let playingQueue = playingQueue {
                    continuation.resume(returning: playingQueue)
                } else {
                    continuation.resume(throwing: AudioPlayerError.moveFailed)
                }
            }
        }
    }

    public func listPlayingQueue() async throws -> PlayingQueue {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "queue") { (playingQueue: PlayingQueue?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let playingQueue = playingQueue {
                    continuation.resume(returning: playingQueue)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    public func playRandomTrack() async throws -> AudioTrack {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "rand") { (audioTrack: AudioTrack?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioTrack = audioTrack {
                    continuation.resume(returning: audioTrack)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    public func playRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "rand/\(artist)") { (audioTrack: AudioTrack?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioTrack = audioTrack {
                    continuation.resume(returning: audioTrack)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    public func playNewRandomTrack() async throws -> AudioTrack {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "newrand") { (audioTrack: AudioTrack?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioTrack = audioTrack {
                    continuation.resume(returning: audioTrack)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    public func playNewRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "newrand/\(artist)") { (audioTrack: AudioTrack?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioTrack = audioTrack {
                    continuation.resume(returning: audioTrack)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    public func clearPlayingQueue() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            self.request(path: "stop") { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    public func pausePlaying() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            self.request(path: "pause") { success, error in
                if success { self.isPaused = true }
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    public func resumePlaying() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            self.request(path: "resume") { success, error in
                if success { self.isPaused = false }
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    public func shuffleQueue() {
        self.request(path: "shuffle") { success, error in
            Log.i("shuffled")
            // XXX refresh queue?
        }
    }

    public func playUntil(date: Date) async throws -> PlayingQueue {
        let timestamp = Int(date.timeIntervalSince1970)
        return try await withCheckedThrowingContinuation { continuation in
            self.requestJson(atPath: "playuntil/\(timestamp)") { (playingQueue: PlayingQueue?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let playingQueue = playingQueue {
                    continuation.resume(returning: playingQueue)
                } else {
                    continuation.resume(throwing: AudioPlayerError.noTrackAvailable)
                }
            }
        }
    }

    // remote queue: audition the gain on the server's currently-playing track
    public func setLivePlaybackGain(decibels: Double) {
        self.request(path: "volume/live/\(decibels)") { _, _ in }
    }
}
