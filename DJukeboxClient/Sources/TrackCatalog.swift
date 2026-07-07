import Foundation
import os
import DJukeboxCommon

// The non-isolated TrackFinderType surface, split out of TrackFetcher (F30).
//
// TrackFetcher is @MainActor (it's a SwiftUI view model), but TrackFinderType is a
// synchronous, non-isolated DJukeboxCommon protocol: it's called off the main actor
// by AVDoghouseAudioPlayer.play() and LocalTracks.download(sha1Hash:), both of which
// are themselves non-isolated @unchecked Sendable types that also conform to
// synchronous DJukeboxCommon protocols the SERVER implements too (AudioPlayerType /
// TrackFinderType) — those can't become async/MainActor without cascading into the
// server's route handlers, so this lookup surface has to stay synchronous and
// callable from any thread.
//
// A frozen snapshot won't do: the catalog is rebuilt whenever the track list
// reloads (e.g. switching local/offline <-> remote), so a one-shot copy would go
// stale the moment TrackFetcher republishes. Making this an actor would force
// track(forHash:)/audioTrack(forHash:) to become async, which is exactly the
// cascade we're avoiding. So this is a plain Sendable class guarding its mutable
// state with a lock (the same OSAllocatedUnfairLock pattern already used by
// AudioLevelMonitor/AudioGainTap/AudioLevelMeter in this target) — live and
// thread-safe, but synchronous.
//
// TrackFetcher owns one of these and delegates its TrackFinderType conformance to
// it; non-isolated consumers (AVDoghouseAudioPlayer, LocalTracks) hold this type
// directly instead of holding TrackFetcher, so they never touch a @MainActor value
// off the main actor.
public final class TrackCatalog: TrackFinderType, @unchecked Sendable {
    // `localTracks` is `any LocalTrackType`, a plain (non-Sendable) protocol
    // existential, so OSAllocatedUnfairLock's generic Sendable constraint won't
    // accept it directly. Box it (UncheckedSendableBox, same escape hatch
    // AVDoghouseAudioPlayer/AudioGainTap already use) — safe because its only
    // conformer, LocalTracks, is itself @unchecked Sendable (thread-safe by
    // construction; see its own comment). trackMap is a value type and genuinely
    // Sendable already.
    private struct State {
        var trackMap: [String: AudioTrack] = [:]
        var localTracks: UncheckedSendableBox<LocalTrackType?> = UncheckedSendableBox(nil)
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // set once at construction (ServerConnection/URL don't change for a
    // TrackFetcher's lifetime); read from any thread when building stream URLs
    private let serverURL: String
    private let authHeaderValue: String

    public init(serverURL: String, authHeaderValue: String) {
        self.serverURL = serverURL
        self.authHeaderValue = authHeaderValue
    }

    // Called by TrackFetcher (on the main actor) whenever the catalog reloads
    // (update(with:) after a fresh track list arrives).
    func update(trackMap: [String: AudioTrack]) {
        state.withLock { $0.trackMap = trackMap }
    }

    // Called by TrackFetcher (on the main actor) once LocalTracks is constructed.
    // Boxed OUTSIDE the lock closure: a @Sendable closure can't capture or return
    // the raw `any LocalTrackType` existential (not Sendable), even when it's
    // being packed into a box that IS Sendable — the box itself has to cross the
    // closure boundary already-built.
    func setLocalTracks(_ localTracks: LocalTrackType?) {
        let box = UncheckedSendableBox(localTracks)
        state.withLock { $0.localTracks = box }
    }

    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        let (localTracksBox, trackMap) = state.withLock { ($0.localTracks, $0.trackMap) }
        let localTracks = localTracksBox.value

        if let localTracks = localTracks,
           let (track, url) = localTracks.track(forHash: sha1Hash)
        {
            return (track, url)
        }

        if let track = trackMap[sha1Hash],
           let url = URL(string: "\(serverURL)/stream/\(authHeaderValue)/\(sha1Hash)")
        {
            return (track, url)
        }
        return nil
    }

    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
        let (localTracksBox, trackMap) = state.withLock { ($0.localTracks, $0.trackMap) }
        let localTracks = localTracksBox.value

        if let localTracks = localTracks,
           let track = localTracks.audioTrack(forHash: sha1Hash)
        {
            return track
        }

        return trackMap[sha1Hash]
    }
}
