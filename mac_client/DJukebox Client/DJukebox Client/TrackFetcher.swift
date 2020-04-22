import Cocoa
import SwiftUI
import CryptoKit

// this is a view model used to update SwiftUI

public class TrackFetcher: ObservableObject {
    var allTracks: [AudioTrack] = []

    @Published var artists: [AudioTrack] = []
    @Published var albums: [AudioTrack] = []
    @Published var tracks: [AudioTrack] = []

    @Published var albumTitle: String
    @Published var trackTitle: String
    
    @Published var playingQueue: [AudioTrack] = []

    let server: ServerType
    
    init(withServer server: ServerType) {
        self.server = server
        self.albumTitle = "Albums"
        self.trackTitle = "Songs"
        refreshTracks()
        refreshQueue()
    }

    func refreshTracks() {
        server.listTracks() { tracks, error in
            if let tracks = tracks {
                var artistMap: [String:AudioTrack] = [:]
                for track in tracks {
                    if track.Album == nil {
                        print("artist \(track.Artist) has orphaned tracks")
                    }
                    artistMap[track.Artist] = track
                }
                DispatchQueue.main.async {
                    self.allTracks = tracks
                    self.artists = Array(artistMap.values).sorted()
                }
            }
        }
    }

    func removeItemFromPlayingQueue(at index: Int) {
        guard index >= 0 else { return }
        guard index < playingQueue.count else { return }

        server.stopPlayingTrack(withHash: playingQueue[index].SHA1) { success, error in
            if success { self.refreshQueue() }
        }
    }
    
    func refreshQueue() {
        server.listPlayingQueue() { tracks, error in
            if let tracks = tracks {
                DispatchQueue.main.async {
                    self.playingQueue = tracks
                }
            }
        }
    }

    // show all tracks for the artist/album combo in the passed AudioTrack
    func showTracks(for audioTrack: AudioTrack) {
        var tracks: [AudioTrack] = []

        let desiredArtist = audioTrack.Artist
        let desiredAlbum = audioTrack.Album

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
        
        DispatchQueue.main.async {
            self.tracks = tracks.sorted()
            if let desiredAlbum = desiredAlbum {
                self.trackTitle = "\(desiredAlbum) songs"
            } else {
                self.trackTitle = "\(desiredArtist) songs"
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
            self.albumTitle = "\(artist) albums"
        }
    }
}
