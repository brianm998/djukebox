import Foundation
import SwiftUI
import CryptoKit
import DJukeboxCommon

// This allows any String, including literals, to be thrown as an Error
extension String: Error {}

public enum QueueType {
    case local
    case remote
}

public struct LocalTrackCache {
    var tracks: [String: URL]
}

// this is a view model used to update SwiftUI
public class TrackFetcher: ObservableObject {
    var allTracks: [AudioTrack] = []

    var trackMap: [String:AudioTrack] = [:]

    var localTracks: LocalTrackType?
    
    // turn on to not use streaming for tracks (offline mode)
    var useLocalContentOnly = false {
        didSet(oldValue) {
            refreshTracks()
        }
    }
    
    // what is shown on the artists list
    @Published var artists: [AudioTrack] = [] // XXX use different model objects for artists and albums

    // what is shown on the albums list
    @Published var albums: [AudioTrack] = []

    // what is shown on the tracks list
    @Published var tracks: [AudioTrack] = []

    // the text at the top of the albums list
    @Published var albumTitle: String

    // the text at the top of the tracks list
    @Published var trackTitle: String

    // currentTrack is the first item in the playing queue, if any
    @Published var currentTrack: AudioTrack?

    // pendingTracks contains of the rest of the playing queue from the server
    @Published var pendingTracks: [AudioTrack] = []

    // this is the direct PlayingQueue json object we get from the server
    @Published var playingQueue: PlayingQueue?

    @Published var searchResults: [AudioTrack] = []

    @Published var progressBarLevel: ProgressBar.State?
    
    @Published var totalDuration: TimeInterval = 0

    @Published var completionTime: Date = Date()
    
    let server: ServerType

    @Published public var audioPlayer: ViewObservableAudioPlayer

    @Published public var queueType: QueueType!
    
    var desiredArtist: String?
    var desiredAlbum: String?
    
    var queues: [QueueType: AsyncAudioPlayerType] = [:]

    public init(withServer server: ServerType) {
        self.server = server
        self.albumTitle = "Albums"
        self.trackTitle = "Songs"
        self.audioPlayer = ViewObservableAudioPlayer()
    }

    public func add(queueType: QueueType, withPlayer player: AsyncAudioPlayerType) {
        queues[queueType] = player
    }
    
    public func watch(queue: QueueType) throws {
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
    
    func search(for searchQuery: String) {
        Log.d("self.allTracks.count \(self.allTracks.count)")

        var results: [AudioTrack] = []

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
        
        DispatchQueue.main.async {
            self.searchResults = results
        }
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
        DispatchQueue.main.async {
            self.allTracks = tracks
            self.artists = Array(artistMap.values).sorted()
            self.trackMap = sha1Map
        }
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

    // show all tracks for the artist/album combo in the passed AudioTrack
    func showTracks(for audioTrack: AudioTrack) {
        var tracks: [AudioTrack] = []

        desiredArtist = audioTrack.Artist
        desiredAlbum = audioTrack.Album

        if let desiredAlbum = desiredAlbum {
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

        self.showAlbums(forArtist: audioTrack.Artist)
        
        DispatchQueue.main.async {
            self.tracks = tracks.sorted()
            if let desiredAlbum = self.desiredAlbum {
                self.trackTitle = "\(desiredAlbum)"
            } else if let desiredArtist = self.desiredArtist {
                self.trackTitle = "\(desiredArtist)"
            } else {
                self.trackTitle = "songs" // XXX
            }
        }
    }
    
    func showAlbums(forArtist artist: String) {
        Log.d("for artist \(artist)")
        var albums: [String] = []

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
        DispatchQueue.main.async {
            self.albums = Array(albumMap.values).sorted()
            self.albumTitle = "\(artist)"
        }
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
        Log.d("cacheQueue")
        localTracks?.clearLocalStore()
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
