import Foundation
import SwiftUI
import CryptoKit

// This allows any String, including literals, to be thrown as an Error
extension String: Error {}

public enum QueueType {
    case local
    case remote
}


// this is a view model used to update SwiftUI
public class TrackFetcher: ObservableObject {
    var allTracks: [AudioTrack] = []

    var trackMap: [String:AudioTrack] = [:]
    
    @Published var artists: [AudioTrack] = [] // XXX use different model objects for artists and albums
    @Published var albums: [AudioTrack] = []
    @Published var tracks: [AudioTrack] = []

    @Published var albumTitle: String
    @Published var trackTitle: String

    @Published var currentTrack: AudioTrack?
    @Published var playingQueue: [AudioTrack] = []

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
    
    fileprivate func updatePlayingQueue(to player: AsyncAudioPlayerType) {
        self.audioPlayer.player = player
        self.refreshQueue()
    }
    
    func search(for searchQuery: String) {
        print("self.allTracks.count \(self.allTracks.count)")

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
    
    public func refreshTracks() {
        server.listTracks() { tracks, error in
            if let tracks = tracks {
                var artistMap: [String:AudioTrack] = [:]
                var sha1Map: [String:AudioTrack] = [:]
                for track in tracks {
                    if track.Album == nil {
                        print("artist \(track.Artist) has orphaned tracks")
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
        }
    }

    func removeItemFromPlayingQueue(at index: Int) {
        guard index >= 0 else { return }
        guard index < playingQueue.count else { return }

        audioPlayer.player?.stopPlayingTrack(withHash: playingQueue[index].SHA1, atIndex: index) { success, error in
            if success { self.refreshQueue() }
        }
    }

    func update(playingQueue: PlayingQueue) {
        DispatchQueue.main.async {
            if playingQueue.tracks.count > 0 {
                self.currentTrack = playingQueue.tracks[0]

                if playingQueue.tracks.count > 1 {
                    self.playingQueue = Array(playingQueue.tracks[1..<playingQueue.tracks.count])
                } else {
                    self.playingQueue = []
                }
            } else {
                self.currentTrack = nil
                self.playingQueue = []
            }
            var totalDuration: TimeInterval = 0
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
        print("for artist \(artist)")
        var albums: [String] = []

        var albumMap: [String:AudioTrack] = [:]

        let singles = "Singles"
        
        for track in allTracks {
            if track.Artist == artist {
                if let album = track.Album {
                    albumMap[album] = track
                } else {
                    albumMap[singles] = track
                    print("missing album for track \(track.Artist) \(track.Title)")
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
