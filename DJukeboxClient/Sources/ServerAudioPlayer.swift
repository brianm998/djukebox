import Foundation
import DJukeboxCommon

// @unchecked Sendable: bridges the (non-isolated) AsyncAudioPlayerType to server
// endpoints. `isPaused`/`playingTrackPosition` are only touched from URLSession
// callbacks and the main thread; treated as internally main-thread-disciplined.
//
// ServerConnection's request/post/requestJson helpers are async throws (F07), so
// every method here just calls them directly with try await -- no continuation
// bridging needed.
public class ServerAudioPlayer: ServerConnection, AsyncAudioPlayerType, @unchecked Sendable {


    public var playingTrackPosition: TimeInterval = 0 // XXX

    public func update(with runtimeState: RuntimeState) {
        Log.w("unimplementd, should not be called")
    }


    // XXX should query server on startup, in case it's already paused (need new api for that)
    public var isPaused = false

    public func playTrack(withHash hash: String) async throws -> AudioTrack {
        try await self.requestJson(atPath: "play/\(hash)")
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
        try await self.request(path: "stop/\(hash)/\(index)")
        return true
    }

    public func movePlayingTrack(withHash hash: String,
                          fromIndex: Int,
                          toIndex: Int) async throws -> PlayingQueue
    {
        try await self.requestJson(atPath: "move/\(hash)/\(fromIndex)/\(toIndex)")
    }

    public func listPlayingQueue() async throws -> PlayingQueue {
        try await self.requestJson(atPath: "queue")
    }

    public func playRandomTrack() async throws -> AudioTrack {
        try await self.requestJson(atPath: "rand")
    }

    public func playRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        try await self.requestJson(atPath: "rand/\(artist)")
    }

    public func playNewRandomTrack() async throws -> AudioTrack {
        try await self.requestJson(atPath: "newrand")
    }

    public func playNewRandomTrack(forArtist artist: String) async throws -> AudioTrack {
        try await self.requestJson(atPath: "newrand/\(artist)")
    }

    public func clearPlayingQueue() async throws -> Bool {
        try await self.request(path: "stop")
        return true
    }

    public func pausePlaying() async throws -> Bool {
        try await self.request(path: "pause")
        self.isPaused = true
        return true
    }

    public func resumePlaying() async throws -> Bool {
        try await self.request(path: "resume")
        self.isPaused = false
        return true
    }

    public func shuffleQueue() {
        Task {
            do {
                try await self.request(path: "shuffle")
                Log.i("shuffled")
                // XXX refresh queue?
            } catch {
                Log.e("could not shuffle queue: \(error)")
            }
        }
    }

    public func playUntil(date: Date) async throws -> PlayingQueue {
        let timestamp = Int(date.timeIntervalSince1970)
        return try await self.requestJson(atPath: "playuntil/\(timestamp)")
    }

    // remote queue: audition the gain on the server's currently-playing track
    public func setLivePlaybackGain(decibels: Double) {
        Task {
            do {
                try await self.request(path: "volume/live/\(decibels)")
            } catch {
                Log.e("could not set live playback gain: \(error)")
            }
        }
    }
}
