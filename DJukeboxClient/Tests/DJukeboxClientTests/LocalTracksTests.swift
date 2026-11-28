import Foundation
import Testing
@testable import DJukeboxClient

struct LocalTracksTests {
    private func makeStore() -> LocalTracks {
        LocalTracks(trackFinder: TrackCatalog(serverURL: "", authHeaderValue: "local"),
                    databaseURL: nil,
                    scanDisk: false)
    }

    private func track(_ hash: String, title: String) -> AudioTrack {
        AudioTrack(Credit: "Credit", Artist: "Artist", Album: "Album", Conductor: nil,
                   Title: title, Filename: "\(hash).mp3", SHA1: hash, Duration: nil,
                   AudioBitrate: nil, SampleRate: nil, TrackNumber: nil,
                   Genre: nil, Year: nil, OriginalDate: nil)
    }

    @Test func insertingKeepsTheCatalogConsistentAndDeduped() {
        let store = makeStore()
        var latestTitle: [String: String] = [:]

        // 500 inserts over 200 distinct hashes, each with its own title
        for i in 0..<500 {
            let hash = "sha\(i % 200)"
            store.insertDownloaded(track(hash, title: "title\(i)"))
            latestTitle[hash] = "title\(i)"
        }

        let tracks = store.downloadedTracks
        let map = store.downloadedTrackMap
        #expect(tracks.count == 200)
        #expect(map.count == 200)
        #expect(Set(tracks.map { $0.SHA1 }) == Set(latestTitle.keys))
        #expect(Set(map.keys) == Set(latestTitle.keys))
        #expect(tracks.allSatisfy { $0.Title == latestTitle[$0.SHA1] })
        #expect(map.allSatisfy { $0.value.SHA1 == $0.key && $0.value.Title == latestTitle[$0.key] })
        #expect(store.audioTrack(forHash: "sha0")?.Title == latestTitle["sha0"])
    }
}
