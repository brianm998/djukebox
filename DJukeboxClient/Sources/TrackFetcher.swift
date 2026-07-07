import Foundation
import SwiftUI
import CryptoKit
import DJukeboxCommon

enum TrackFetcherError: Error {
    case noPlayer(PlayingQueueType)
}

public enum PlayingQueueType: String, Decodable, Encodable {
    case local
    case remote
}

// How much of a browse-list row is cached locally for offline play: an artist's
// whole catalog, one album, or a single song. Drives the row tint — full = green,
// partial = amber, none = normal text. (Songs are all-or-nothing, so they only ever
// resolve to .full or .none.) See DJTheme.cacheFull / cachePartial / cacheNone.
public enum CacheStatus {
    case none
    case partial
    case full

    public var color: Color {
        switch self {
        case .full:    return DJTheme.cacheFull
        case .partial: return DJTheme.cachePartial
        case .none:    return DJTheme.cacheNone
        }
    }
}

public struct LocalTrackCache {
    var tracks: [String: URL]
}

// this is a view model used to update SwiftUI
//
// @MainActor: this is a SwiftUI view model. It used to also have to be the
// client's TrackFinderType (a non-isolated DJukeboxCommon protocol the audio
// players call off the main thread), which meant it couldn't be @MainActor and
// every @Published mutation had to be manually routed to the main thread via
// DispatchQueue.main.async. F30 split that non-isolated lookup surface out into
// TrackCatalog (see TrackCatalog.swift); TrackFetcher now delegates its
// TrackFinderType conformance to an owned `catalog` and is free to be a normal
// @MainActor view model. Non-isolated consumers (AVDoghouseAudioPlayer,
// LocalTracks) hold `catalog` directly instead of holding TrackFetcher.
@MainActor
public class TrackFetcher: ObservableObject {
    var allTracks: [AudioTrack] = []

    var trackMap: [String:AudioTrack] = [:]

    // The non-isolated TrackFinderType surface; see TrackCatalog.swift. Kept in
    // sync with trackMap/localTracks below so non-isolated consumers (which hold
    // this directly) always see the current catalog.
    public let catalog: TrackCatalog

    var localTracks: LocalTrackType? {
        didSet { catalog.setLocalTracks(localTracks) }
    }

    // turn on to not use streaming for tracks (offline mode)
    public var useLocalContentOnly = false {
        didSet(oldValue) {
            // not @Published (can't combine a wrapper with didSet), so nudge
            // observers directly — the offline/local UI keys off this flag
            objectWillChange.send()
            refreshTracks()
        }
    }

    var runtimeState: RuntimeState {
        return RuntimeState(isPaused: self.audioPlayer.player?.isPaused ?? false,
                            isOffline: self.useLocalContentOnly,
                            playingQueue: self.queueType,
                            playingTrack: currentTrack?.SHA1,
                            playingTrackPosition: self.audioPlayer.player?.playingTrackPosition ?? 0,
                            pendingTracks: self.pendingTracks.map { $0.SHA1 })
    }

    fileprivate var initialRuntimeState: RuntimeState?

    // this is called after we get the track list from the server to put the client in the same place as before
    fileprivate func maybeDoInitialSetup() {
        Log.i(self.initialRuntimeState)
        if let initialRuntimeState = self.initialRuntimeState {
            Log.i(initialRuntimeState)
            self.initialRuntimeState = nil

            // only restore saved state into the local player; the server manages its own queue
            guard queueType == .local else { return }
            audioPlayer.player?.update(with: initialRuntimeState)
        }
    }
    
    func initialize(with runtimeState: RuntimeState) {
        if runtimeState.playingQueue == .local {
            if trackMap.count == 0 {
                // delay this step until we've got a trackMap
                Log.i("trackMap count \(trackMap.count)")
                self.initialRuntimeState = runtimeState
                Log.i(self.initialRuntimeState)
            } else {
                if let playingTrack = runtimeState.playingTrack {
                    self.currentTrack = self.catalog.audioTrack(forHash: playingTrack) as? AudioTrack
                }
                self.pendingTracks = runtimeState.pendingTracks.map {
                    self.catalog.audioTrack(forHash: $0) as! AudioTrack
                }
            }
        }
        self.useLocalContentOnly = runtimeState.isOffline
        do {
            try self.watch(queue: runtimeState.playingQueue)
        } catch {
            Log.e("can't watch queue: \(error)") // XXX handle this better
        }
    }
    
    // what is shown on the artists list
    @Published public var artists: [AudioTrack] = [] // XXX use different model objects for artists and albums

    public func artists(matching queryString: String) -> [AudioTrack] {
        if queryString.count == 0 {
            return self.artists
        } else {
            // filter artists by
            var ret: [AudioTrack] = []

            let lowerCaseQuery = queryString.lowercased()

            for artist in artists {
                if artist.Artist.lowercased().contains(lowerCaseQuery) {
                    ret.append(artist)
                }
            }
            return ret
        }
    }
    
    // what is shown on the albums list
    @Published public var albums: [AudioTrack] = []

    // what is shown on the tracks list
    @Published public var tracks: [AudioTrack] = []

    // Local-cache tint maps for the browse lists (recomputeCacheStatus). Keyed by
    // artist name and by albumStatusKey(artist:album:); cachedTrackSHA1s is the flat
    // set the songs list checks per row. Recomputed whenever the catalog or the set
    // of cached tracks changes. These are derived from the CURRENT catalog, so in
    // offline mode — where the catalog is exactly the cached tracks — every row is
    // fully cached (green).
    @Published public var artistCacheStatus: [String: CacheStatus] = [:]
    @Published public var albumCacheStatus: [String: CacheStatus] = [:]
    @Published public var cachedTrackSHA1s: Set<String> = []

    // the text at the top of the albums list
    @Published public var albumTitle: String

    // the text at the top of the tracks list
    @Published public var trackTitle: String

    // currentTrack is the first item in the playing queue, if any
    @Published public var currentTrack: AudioTrack?

    // pendingTracks contains of the rest of the playing queue from the server
    @Published public var pendingTracks: [AudioTrack] = []

    // this is the direct PlayingQueue json object we get from the server
    @Published public var playingQueue: PlayingQueue?

    @Published public var progressBarLevel: ProgressBar.State?
    
    @Published public var totalDuration: TimeInterval = 0

    @Published public var completionTime: Date = Date()
    
    let server: ServerType

    @Published public var audioPlayer: ViewObservableAudioPlayer

    @Published public var queueType: PlayingQueueType!
    
    var desiredArtist: String?
    var desiredAlbum: String?

    // the artist whose album list is currently shown in the mac/iPad middle column,
    // remembered so it can be re-derived when the catalog changes (e.g. going local)
    var shownAlbumsArtist: String?

    var queues: [PlayingQueueType: AsyncAudioPlayerType] = [:]

    public init(withServer server: ServerType) {
        self.server = server
        self.catalog = TrackCatalog(serverURL: server.url, authHeaderValue: server.authHeaderValue)
        self.albumTitle = "Albums"
        self.trackTitle = "Songs"
        self.audioPlayer = ViewObservableAudioPlayer()
    }

    public func add(queueType: PlayingQueueType, withPlayer player: AsyncAudioPlayerType) {
        queues[queueType] = player
    }
    
    public func watch(queue: PlayingQueueType) throws {
        if let player = queues[queue] {
            self.updatePlayingQueue(to: player)
            self.queueType = queue
        } else {
            throw TrackFetcherError.noPlayer(queue)
        }
    }
    
    fileprivate func updatePlayingQueue(to player: AsyncAudioPlayerType) { // XXX rename this to changeXXX
        self.audioPlayer.player = player
        self.refreshQueue()
    }
    
    func search(for searchQuery: String) -> [AudioTrack] {
        Log.d("self.allTracks.count \(self.allTracks.count)")

        var results: [AudioTrack] = []

        guard searchQuery.count > 3 else { return results }
        
        let lowerCaseQuery = searchQuery.lowercased()
        
        for track in self.allTracks {
            if track.Artist.lowercased().contains(lowerCaseQuery) {
                results.append(track)
            } else if let album = track.Album,
                album.lowercased().contains(lowerCaseQuery) {
                results.append(track)
            } else if track.Title.lowercased().contains(lowerCaseQuery) {
                results.append(track)
            }
        }

        return results
    }
    
    // updates the ui to show the current set of tracks we have
    fileprivate func update(with tracks: [AudioTrack]) {
        var artistMap: [String:AudioTrack] = [:]
        var sha1Map: [String:AudioTrack] = [:]
        for track in tracks {
            if track.Album == nil {
                Log.d("artist \(track.Artist) has orphaned tracks")
            }
            artistMap[track.Artist] = track
            sha1Map[track.SHA1] = track
        }
        self.allTracks = tracks
        self.artists = Array(artistMap.values).sorted()
        self.trackMap = sha1Map
        self.catalog.update(trackMap: sha1Map)
        self.reapplyBrowseColumns()
        self.recomputeCacheStatus()
        self.maybeDoInitialSetup()
    }

    // After the catalog is (re)loaded — e.g. switching to local/offline — the mac /
    // iPad 3-column browse view would otherwise keep showing the previous catalog's
    // albums and tracks, since those columns are only refreshed on a tap
    // (showAlbums / showTracks). Re-derive them for the current selection so all
    // three columns reflect the new catalog. (The iPhone navigation views derive
    // their own lists live and don't depend on this.)
    fileprivate func reapplyBrowseColumns() {
        if let artist = self.shownAlbumsArtist {
            self.albums = self.albums(forArtist: artist)
        }
        if let artist = self.desiredArtist {
            self.tracks = self.allTracks.filter {
                $0.Artist == artist && $0.Album == self.desiredAlbum
            }.sorted()
        }
    }

    public func shuffleQueue() {
        self.audioPlayer.player?.shuffleQueue()
    }
    
    public func refreshTracks() {
        if useLocalContentOnly {
            if let tracks = localTracks?.downloadedTracks {
                self.update(with: tracks)
            } else {
                self.update(with: []) // XXX should show an error here
            }
        } else {
            Task {
                do {
                    let tracks = try await server.listTracks()
                    self.update(with: tracks)
                } catch {
                    Log.e("could not list tracks: \(error)")
                }
            }
        }
    }

    func removeItemFromPlayingQueue(at index: Int) {
        guard index >= 0 else { return }
        guard index < pendingTracks.count else { return }

        let hash = pendingTracks[index].SHA1
        Task {
            do {
                let success = try await audioPlayer.player?.stopPlayingTrack(withHash: hash, atIndex: index)
                if success == true { self.refreshQueue() }
            } catch {
                Log.e("could not stop playing track: \(error)")
            }
        }
    }

    func update(playingQueue: PlayingQueue) {
        self.playingQueue = playingQueue

        if playingQueue.tracks.count > 0 {
            self.currentTrack = playingQueue.tracks[0]

            if playingQueue.tracks.count > 1 {
                self.pendingTracks = Array(playingQueue.tracks[1..<playingQueue.tracks.count])
            } else {
                self.pendingTracks = []
            }
        } else {
            self.currentTrack = nil
            self.pendingTracks = []
        }
        // keep the volume-button label in sync with whatever is now playing
        let gainSha1 = self.currentTrack?.SHA1
        if gainSha1 != self.lastGainSha1 {
            self.lastGainSha1 = gainSha1
            if let gainSha1 {
                self.refreshSavedGain(forHash: gainSha1)
            } else {
                self.currentTrackGainDB = 0
            }
        }
        var totalDuration: TimeInterval = 0
        // XXX make this track the PlayingQueue directly
        if let duration = playingQueue.playingTrackDuration,
           let position = playingQueue.playingTrackPosition
        {
            self.progressBarLevel = ProgressBar.State(level: position, max: duration)
            totalDuration = duration - position
        } else {
            self.progressBarLevel = nil
        }
        for (index, track) in playingQueue.tracks.enumerated() {
            if index > 0 { totalDuration += track.timeInterval ?? 0 }
        }
        self.totalDuration = totalDuration
        self.completionTime = Date(timeIntervalSinceNow: totalDuration)
    }
    
    public func refreshQueue() {
        Task {
            do {
                if let queue = try await audioPlayer.player?.listPlayingQueue() {
                    self.update(playingQueue: queue)
                }
            } catch {
                Log.e("could not list playing queue: \(error)")
            }
        }
    }

    // Advance just the progress bar from a pushed position tick (the server sends
    // these a couple of times a second while playing, between full queue frames),
    // so the bar moves without resending the whole queue. A nil duration/position
    // means "nothing playing" → clear the bar.
    public func updateProgress(position: TimeInterval?, duration: TimeInterval?) {
        if let duration, let position = position, duration > 0 {
            self.progressBarLevel = ProgressBar.State(level: position, max: duration)
        } else {
            self.progressBarLevel = nil
        }
    }

    public func tracks(for audioTrack: AudioTrack) -> [AudioTrack] {
        var tracks: [AudioTrack] = []

        desiredArtist = audioTrack.Artist
        desiredAlbum = audioTrack.Album

        if let desiredAlbum {
            for track in allTracks {
                if track.Artist == desiredArtist,
                   track.Album == desiredAlbum
                {
                    tracks.append(track)
                }
            }
        } else {
            for track in allTracks {
                if track.Artist == desiredArtist,
                   track.Album == nil
                {
                    tracks.append(track)
                }
            }
        }
        return tracks
    }

    // show all tracks for the artist/album combo in the passed AudioTrack
    func showTracks(for audioTrack: AudioTrack) {
        let tracks = self.tracks(for: audioTrack)

        self.showAlbums(forArtist: audioTrack.Artist)

        self.tracks = tracks.sorted()
        if let desiredAlbum = self.desiredAlbum {
            self.trackTitle = "\(desiredAlbum)"
        } else if let desiredArtist = self.desiredArtist {
            self.trackTitle = "\(desiredArtist)"
        } else {
            self.trackTitle = "songs" // XXX
        }
    }

    public func albums(forArtist artist: String) -> [AudioTrack] {
        Log.d("for artist \(artist)")

        var albumMap: [String:AudioTrack] = [:]

        let singles = "Singles"

        for track in allTracks {
            if track.Artist == artist {
                if let album = track.Album {
                    albumMap[album] = track
                } else {
                    albumMap[singles] = track
                    Log.d("missing album for track \(track.Artist) \(track.Title)")
                }
            }
        }
        return Array(albumMap.values).sorted()
    }

    func showAlbums(forArtist artist: String) {
        let albums = self.albums(forArtist: artist)
        Log.d("show albums for \(artist)")
        self.shownAlbumsArtist = artist
        self.albums = albums
        self.albumTitle = "\(artist)"
    }

    public func cacheTracks(forArtist artist: String) {
        self.cache(tracks: self.tracks(forArtist: artist))
    }

    public func tracks(forArtist artist: String) -> [AudioTrack] {
        var ret: [AudioTrack] = []
        for track in allTracks {
            if track.Artist == artist {
                ret.append(track)
            }
        }
        return ret
    }

    // Pure filter (no side effects) for a bound songs panel: an artist's tracks
    // on a specific album (nil album = the artist's singles).
    public func tracks(forArtist artist: String, album: String?) -> [AudioTrack] {
        allTracks.filter { $0.Artist == artist && $0.Album == album }.sorted()
    }

    public func clearPlayingQueue() {
        Task {
            do {
                let success = try await self.audioPlayer.player?.clearPlayingQueue()
                Log.d("clear queue: \(success)")
            } catch {
                Log.e("DOH \(error)")
            }
            self.refreshQueue()
        }
    }

    public func playRandomTrack() {
        Task {
            do {
                if let audioTrack = try await self.audioPlayer.player?.playRandomTrack() {
                    Log.d("random enqueued: \(audioTrack.Title)")
                }
            } catch {
                Log.e("DOH \(error)")
            }
            self.refreshQueue()
        }
    }

    public func playNewRandomTrack() {
        Task {
            do {
                if let audioTrack = try await self.audioPlayer.player?.playNewRandomTrack() {
                    Log.d("new random enqueued: \(audioTrack.Title)")
                }
            } catch {
                Log.e("DOH error: \(error)")
            }
            self.refreshQueue()
        }
    }

    public func playUntil(date: Date) {
        Task {
            do {
                _ = try await self.audioPlayer.player?.playUntil(date: date)
            } catch {
                Log.e("could not play until \(date): \(error)")
            }
            self.refreshQueue()
        }
    }

    // Persist a playback-gain adjustment (in dB) for a track, scoping it to just
    // that track, its whole album, or its whole artist. The server stores it and
    // applies it the next time a matching track plays. "artist"/"album" key off
    // the Artist field (and Album), matching how the catalog is browsed.
    public func setVolume(decibels: Double, scope: VolumeScope, for track: AudioTrack) {
        let adjustment: VolumeAdjustment
        switch scope {
        case .track:
            adjustment = VolumeAdjustment(scope: "track", sha1: track.SHA1, decibels: decibels)
        case .album:
            guard let album = track.Album else {
                Log.e("cannot set album volume: \(track.Title) has no album")
                return
            }
            adjustment = VolumeAdjustment(scope: "album", artist: track.Artist,
                                          album: album, decibels: decibels)
        case .artist:
            adjustment = VolumeAdjustment(scope: "artist", artist: track.Artist, decibels: decibels)
        }
        Task {
            do {
                try await server.setVolumeAdjustment(adjustment)
                Log.d("set \(scope) volume to \(decibels) dB for \(track.Title)")
                // refresh the button label to the new effective gain for this track
                self.refreshSavedGain(forHash: track.SHA1)
            } catch {
                Log.e("could not set \(scope) volume: \(error)")
            }
        }
    }

    // Live-audition a gain on whatever is playing right now (not persisted) so the
    // user hears the change while dragging the slider. Routes through the active
    // player, so it works for both the server (remote) and local playback queues.
    // The master attenuation is folded in so the audition matches what will play.
    public func previewVolume(decibels: Double) {
        audioPlayer.player?.setLivePlaybackGain(decibels: decibels + masterGainDB)
    }

    // MARK: - master volume

    // The single top-level master gain (dB, <= 0 = a reduction from full volume).
    // Published so the master control reflects it; it composes with the per-track/
    // album/artist gain (previewVolume folds it into every audition, the server
    // folds it into server playback, and Client folds it into local playback).
    @Published public var masterGainDB: Double = 0

    private let masterReductionLimit = 30.0   // reduction-only: -30 dB … 0 dB (full)

    // Pull the current master level from the server (it is global, so another
    // client may have changed it). Views call this on appear; Client on startup.
    public func refreshMasterGain() {
        Task {
            do {
                let db = try await server.masterGain()
                self.masterGainDB = db ?? 0
            } catch {
                Log.e("could not refresh master gain: \(error)")
            }
        }
    }

    // Live-audition a new master level on whatever is playing (not yet persisted),
    // re-applying the current track's saved gain with the new master folded in.
    public func previewMasterGain(decibels: Double) {
        masterGainDB = max(-masterReductionLimit, min(0, decibels))
        previewVolume(decibels: currentTrackGainDB)
    }

    // Persist the current master level to the server (call when the knob settles).
    public func commitMasterGain() {
        Task {
            do {
                try await server.setMasterGain(masterGainDB)
            } catch {
                Log.e("could not set master volume: \(error)")
            }
        }
    }

    // The currently-playing track's saved gain (dB), published for the volume
    // control to pre-fill from. refreshCurrentTrackGain() fetches it from the
    // server and updates this on the main thread (views observe it); we avoid
    // threading a caller closure across the async boundary (Swift 6 data-race).
    @Published public var currentTrackGainDB: Double = 0

    // the sha1 currentTrackGainDB was last fetched for, so update(playingQueue:)
    // only re-fetches when the playing track actually changes
    private var lastGainSha1: String?

    public func refreshSavedGain(forHash hash: String) {
        Task {
            do {
                let db = try await server.savedGain(forHash: hash)
                self.currentTrackGainDB = db ?? 0
            } catch {
                Log.e("could not refresh saved gain: \(error)")
            }
        }
    }

    // MARK: - local cache status

    // A stable key for an (artist, album) pair used by albumCacheStatus. A nil album
    // is the artist's "Singles" bucket. Control-character separators keep artist and
    // album names from colliding across the join.
    public static func albumStatusKey(artist: String, album: String?) -> String {
        return "\(artist)\u{1}\(album ?? "\u{2}singles")"
    }

    // The set of locally cached tracks may have changed (a download finished, the
    // cache was cleared, or the reconcile scan pruned a stale row). Recompute the
    // tint maps on the main queue, serialized with the other catalog mutations.
    // Called by LocalTracks.
    public func cacheDidChange() {
        self.recomputeCacheStatus()
    }

    // Rebuild artistCacheStatus / albumCacheStatus / cachedTrackSHA1s from the
    // current catalog (allTracks) and the set of locally cached tracks. Main-queue
    // only: allTracks and localTracks.downloadedTrackMap are both mutated there, and
    // the @Published results publish on the main thread. One O(allTracks) pass; it
    // runs on catalog reload and between (network-throttled) cache downloads.
    fileprivate func recomputeCacheStatus() {
        let cachedSHA1s: Set<String>
        if let map = localTracks?.downloadedTrackMap {
            cachedSHA1s = Set(map.keys)
        } else {
            cachedSHA1s = []
        }

        var artistTotal: [String: Int] = [:]
        var artistCached: [String: Int] = [:]
        var albumTotal: [String: Int] = [:]
        var albumCached: [String: Int] = [:]

        for track in allTracks {
            let isCached = cachedSHA1s.contains(track.SHA1)
            artistTotal[track.Artist, default: 0] += 1
            if isCached { artistCached[track.Artist, default: 0] += 1 }

            let albumKey = Self.albumStatusKey(artist: track.Artist, album: track.Album)
            albumTotal[albumKey, default: 0] += 1
            if isCached { albumCached[albumKey, default: 0] += 1 }
        }

        func status(cached: Int, total: Int) -> CacheStatus {
            if total == 0 || cached == 0 { return .none }
            return cached >= total ? .full : .partial
        }

        var artistStatus: [String: CacheStatus] = [:]
        for (artist, total) in artistTotal {
            artistStatus[artist] = status(cached: artistCached[artist] ?? 0, total: total)
        }
        var albumStatus: [String: CacheStatus] = [:]
        for (key, total) in albumTotal {
            albumStatus[key] = status(cached: albumCached[key] ?? 0, total: total)
        }

        self.artistCacheStatus = artistStatus
        self.albumCacheStatus = albumStatus
        self.cachedTrackSHA1s = cachedSHA1s
    }
}

// tell the client which url to use for which track hash. TrackFetcher itself
// doesn't conform to TrackFinderType any more (F30) — that non-isolated surface
// now lives on `catalog` (see TrackCatalog.swift), which non-isolated consumers
// (AVDoghouseAudioPlayer, LocalTracks) hold directly. These conveniences stay on
// TrackFetcher because they touch @MainActor-only state (localTracks,
// currentTrack, pendingTracks).
extension TrackFetcher {
    public func clearCache() {
        localTracks?.clearLocalStore()
    }

    public func cache(tracks: [AudioTrack]) {
        Task {
            await self.cacheSequentially(tracks: tracks)
        }
    }

    private func cacheSequentially(tracks: [AudioTrack]) async {
        for track in tracks {
            Log.d("caching track \(track.SHA1)")
            _ = await withCheckedContinuation { continuation in
                localTracks?.keepLocal(sha1Hash: track.SHA1) { success in
                    continuation.resume(returning: success)
                }
            }
        }
        Log.i("cache done")
    }
    
    public func cacheQueue() {
        if let localTracks {
            if let currentTrack {
                localTracks.keepLocal(sha1Hash: currentTrack.SHA1) { success in
                    Log.w(success)
                }
            }
            for track in pendingTracks {
                localTracks.keepLocal(sha1Hash: track.SHA1) { success in
                    Log.w(success)
                }
            }
        }
    }
}
