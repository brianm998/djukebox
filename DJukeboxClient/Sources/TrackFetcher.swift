import Foundation
import SwiftUI
import CryptoKit
import DJukeboxCommon

// This allows any String, including literals, to be thrown as an Error
extension String: Error {}

public enum PlayingQueueType: String, Decodable, Encodable {
    case local
    case remote
}

public struct LocalTrackCache {
    var tracks: [String: URL]
}

// this is a view model used to update SwiftUI
//
// @unchecked Sendable: this is both a SwiftUI view model and the client's
// TrackFinderType (a non-isolated DJukeboxCommon protocol the audio players call
// off the main thread), so it can't be @MainActor. Every @Published mutation is
// routed to the main thread via DispatchQueue.main.async; the catalog maps
// (allTracks / trackMap) are built off-main then published on-main. See the
// client concurrency note in AsyncAudioPlayer.
public class TrackFetcher: ObservableObject, @unchecked Sendable {
    var allTracks: [AudioTrack] = []

    var trackMap: [String:AudioTrack] = [:]

    var localTracks: LocalTrackType?
    
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
                    self.currentTrack = self.audioTrack(forHash: playingTrack) as? AudioTrack
                }
                self.pendingTracks = runtimeState.pendingTracks.map {
                    self.audioTrack(forHash: $0) as! AudioTrack
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
    
    // what is shown on the bands list
    @Published public var bands: [AudioTrack] = [] // XXX use different model objects for bands and albums

    public func bands(matching queryString: String) -> [AudioTrack] {
        if queryString.count == 0 {
            return self.bands
        } else {
            // filter bands by
            var ret: [AudioTrack] = []

            let lowerCaseQuery = queryString.lowercased()
            
            for band in bands {
                if band.Band.lowercased().contains(lowerCaseQuery) {
                    ret.append(band)
                }
            }
            return ret
        }
    }
    
    // what is shown on the albums list
    @Published public var albums: [AudioTrack] = []

    // what is shown on the tracks list
    @Published public var tracks: [AudioTrack] = []

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
    
    var desiredBand: String?
    var desiredAlbum: String?

    // the band whose album list is currently shown in the mac/iPad middle column,
    // remembered so it can be re-derived when the catalog changes (e.g. going local)
    var shownAlbumsBand: String?

    var queues: [PlayingQueueType: AsyncAudioPlayerType] = [:]

    public init(withServer server: ServerType) {
        self.server = server
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
            throw "no player for queue type \(queue)"
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
            if track.Band.lowercased().contains(lowerCaseQuery) {
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
        var bandMap: [String:AudioTrack] = [:]
        var sha1Map: [String:AudioTrack] = [:]
        for track in tracks {
            if track.Album == nil {
                Log.d("band \(track.Band) has orphaned tracks")
            }
            bandMap[track.Band] = track
            sha1Map[track.SHA1] = track
        }
        DispatchQueue.main.async {
            self.allTracks = tracks
            self.bands = Array(bandMap.values).sorted()
            self.trackMap = sha1Map
            self.reapplyBrowseColumns()
            self.maybeDoInitialSetup()
        }
    }

    // After the catalog is (re)loaded — e.g. switching to local/offline — the mac /
    // iPad 3-column browse view would otherwise keep showing the previous catalog's
    // albums and tracks, since those columns are only refreshed on a tap
    // (showAlbums / showTracks). Re-derive them for the current selection so all
    // three columns reflect the new catalog. (The iPhone navigation views derive
    // their own lists live and don't depend on this.)
    fileprivate func reapplyBrowseColumns() {
        if let band = self.shownAlbumsBand {
            self.albums = self.albums(forBand: band)
        }
        if let band = self.desiredBand {
            self.tracks = self.allTracks.filter {
                $0.Band == band && $0.Album == self.desiredAlbum
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
            server.listTracks() { tracks, error in
                if let tracks = tracks {
                    self.update(with: tracks)
                }
            }
        }
    }

    func removeItemFromPlayingQueue(at index: Int) {
        guard index >= 0 else { return }
        guard index < pendingTracks.count else { return }

        audioPlayer.player?.stopPlayingTrack(withHash: pendingTracks[index].SHA1, atIndex: index) { success, error in
            if success { self.refreshQueue() }
        }
    }

    func update(playingQueue: PlayingQueue) {
        DispatchQueue.main.async {
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
                if let gainSha1 = gainSha1 {
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
    }
    
    public func refreshQueue() {
        audioPlayer.player?.listPlayingQueue() { playingQueue, error in
            if let queue = playingQueue { self.update(playingQueue: queue) }
        }
    }

    public func tracks(for audioTrack: AudioTrack) -> [AudioTrack] {
        var tracks: [AudioTrack] = []

        desiredBand = audioTrack.Band
        desiredAlbum = audioTrack.Album

        if let desiredAlbum = desiredAlbum {
            for track in allTracks {
                if track.Band == desiredBand,
                   track.Album == desiredAlbum
                {
                    tracks.append(track)
                }
            }
        } else {
            for track in allTracks {
                if track.Band == desiredBand,
                   track.Album == nil
                {
                    tracks.append(track)
                }
            }
        }
        return tracks
    }
    
    // show all tracks for the band/album combo in the passed AudioTrack
    func showTracks(for audioTrack: AudioTrack) {
        var tracks = self.tracks(for: audioTrack)

        self.showAlbums(forBand: audioTrack.Band)
        
        DispatchQueue.main.async {
            self.tracks = tracks.sorted()
            if let desiredAlbum = self.desiredAlbum {
                self.trackTitle = "\(desiredAlbum)"
            } else if let desiredBand = self.desiredBand {
                self.trackTitle = "\(desiredBand)"
            } else {
                self.trackTitle = "songs" // XXX
            }
        }
    }
    
    public func albums(forBand band: String) -> [AudioTrack] {
        Log.d("for band \(band)")

        var albumMap: [String:AudioTrack] = [:]

        let singles = "Singles"
        
        for track in allTracks {
            if track.Band == band {
                if let album = track.Album {
                    albumMap[album] = track
                } else {
                    albumMap[singles] = track
                    Log.d("missing album for track \(track.Band) \(track.Title)")
                }
            }
        }
        return Array(albumMap.values).sorted()
    }
    
    func showAlbums(forBand band: String) {
        let albums = self.albums(forBand: band)
        DispatchQueue.main.async {
            Log.d("show albums for \(band)")
            self.shownAlbumsBand = band
            self.albums = albums
            self.albumTitle = "\(band)"
        }
    }

    public func cacheTracks(forBand band: String) {
        self.cache(tracks: self.tracks(forBand: band))
    }

    public func tracks(forBand band: String) -> [AudioTrack] {
        var ret: [AudioTrack] = []
        for track in allTracks {
            if track.Band == band {
                ret.append(track)
            }
        }
        return ret
    }

    // Pure filter (no side effects) for a bound songs panel: a band's tracks on a
    // specific album (nil album = the band's singles).
    public func tracks(forBand band: String, album: String?) -> [AudioTrack] {
        allTracks.filter { $0.Band == band && $0.Album == album }.sorted()
    }

    public func clearPlayingQueue() {
        self.audioPlayer.player?.clearPlayingQueue() { audioTrack, error in
            if let error = error {
                Log.e("DOH")
            } else {
                Log.d("clear queue: \(audioTrack)")
            }
            self.refreshQueue()
        }
    }

    public func playRandomTrack() {
        self.audioPlayer.player?.playRandomTrack() { audioTrack, error in
            if let error = error {
                Log.e("DOH")
            } else if let audioTrack = audioTrack {
                Log.d("random enqueued: \(audioTrack.Title)")
            }
            self.refreshQueue()
        }
    }

    public func playNewRandomTrack() {
        self.audioPlayer.player?.playNewRandomTrack() { audioTrack, error in
            if let error = error {
                Log.e("DOH error: \(error)")
            } else if let audioTrack = audioTrack {
                Log.d("new random enqueued: \(audioTrack.Title)")
            }
            self.refreshQueue()
        }
    }

    public func playUntil(date: Date) {
        self.audioPlayer.player?.playUntil(date: date) { playingQueue, error in
            self.refreshQueue()
        }
    }

    // Persist a playback-gain adjustment (in dB) for a track, scoping it to just
    // that track, its whole album, or its whole artist. The server stores it and
    // applies it the next time a matching track plays. "artist"/"album" key off
    // the Band field (and Album), matching how the catalog is browsed.
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
            adjustment = VolumeAdjustment(scope: "album", band: track.Band,
                                          album: album, decibels: decibels)
        case .artist:
            adjustment = VolumeAdjustment(scope: "artist", band: track.Band, decibels: decibels)
        }
        server.setVolumeAdjustment(adjustment) { success, error in
            if let error = error {
                Log.e("could not set \(scope) volume: \(error)")
            } else {
                Log.d("set \(scope) volume to \(decibels) dB for \(track.Title)")
                // refresh the button label to the new effective gain for this track
                self.refreshSavedGain(forHash: track.SHA1)
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
        server.masterGain { db, _ in
            DispatchQueue.main.async { self.masterGainDB = db ?? 0 }
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
        server.setMasterGain(masterGainDB) { _, error in
            if let error = error { Log.e("could not set master volume: \(error)") }
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
        server.savedGain(forHash: hash) { db, _ in
            DispatchQueue.main.async { self.currentTrackGainDB = db ?? 0 }
        }
    }
}

// tell the client which url to use for which track hash
extension TrackFetcher: TrackFinderType {
    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {

        if let localTracks = localTracks,
           let (track, url) = localTracks.track(forHash: sha1Hash)
        {
            return (track, url)
        }
        
        if let track = self.trackMap[sha1Hash],
           let url = URL(string: "\(self.server.url)/stream/\(self.server.authHeaderValue)/\(sha1Hash)")
        {
            //Log.d(url)
            return (track, url)
        }
        return nil
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {

        if let localTracks = localTracks,
           let track = localTracks.audioTrack(forHash: sha1Hash)
        {
            return track
        }
        
        if let track = self.trackMap[sha1Hash] {
            return track
        }
        return nil
    }

    public func clearCache() {
        localTracks?.clearLocalStore()
    }

    public func cache(tracks: [AudioTrack]) {
        self.recursivelyCache(tracks: tracks)
        /*
        for track in tracks {
            localTracks?.keepLocal(sha1Hash: track.SHA1) { success in
                Log.d("success \(success)")
            }
        }
*/
    }

    fileprivate func recursivelyCache(tracks: [AudioTrack]) {
        guard tracks.count > 0 else {
            Log.w("cache done")
            return
        }

        var rest = tracks

        let nextTrack = rest.removeFirst()

        Log.d("caching track \(nextTrack.SHA1)")

        // capture an immutable copy: the @Sendable keepLocal completion can't
        // reference the mutable `rest` binding
        let remaining = rest
        localTracks?.keepLocal(sha1Hash: nextTrack.SHA1) { success in
            //Log.d("cache download success: \(success)")
            self.recursivelyCache(tracks: remaining)
        }
    }
    
    public func cacheQueue() {
        if let localTracks = localTracks {
            if let currentTrack = currentTrack {
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
