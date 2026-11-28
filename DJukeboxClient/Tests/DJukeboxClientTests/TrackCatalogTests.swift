import Foundation
import Testing
import DJukeboxCommon
@testable import DJukeboxClient

// Resolves the given hashes to the given URLs, as if they were downloaded.
final class FakeLocalTracks: LocalTrackType {
    let urls: [String: URL]

    init(_ urls: [String: URL]) { self.urls = urls }

    var downloadedTrackMap: [String: AudioTrack] {
        Dictionary(uniqueKeysWithValues: urls.keys.map { ($0, makeTrack($0)) })
    }
    var downloadedTracks: [AudioTrack] { Array(downloadedTrackMap.values) }

    func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        urls[sha1Hash].map { (makeTrack(sha1Hash), $0) }
    }
    func audioTrack(forHash sha1Hash: String) -> AudioTrackType? { downloadedTrackMap[sha1Hash] }
    func keepLocal(sha1Hash: String, closure: @escaping @Sendable (Bool) -> Void) { closure(false) }
    func clearLocalStore() {}
}

struct TrackCatalogTests {
    private func makeCatalog(serverURL: String) -> TrackCatalog {
        let catalog = TrackCatalog(serverURL: serverURL, authHeaderValue: "tok")
        catalog.update(trackMap: ["a": makeTrack("a")])
        return catalog
    }

    @Test(arguments: ["", "host:1234"])
    func noStreamURLWithoutAServerHost(serverURL: String) {
        let catalog = makeCatalog(serverURL: serverURL)

        #expect(catalog.track(forHash: "a") == nil)
        #expect(catalog.audioTrack(forHash: "a")?.SHA1 == "a")
    }

    @Test func streamURLPointsAtTheServer() throws {
        let catalog = makeCatalog(serverURL: "http://host:1234")

        let (_, url) = try #require(catalog.track(forHash: "a"))

        #expect(url.host == "host")
        #expect(url.absoluteString == "http://host:1234/stream/tok/a")
    }

    @Test func localTrackResolvesWithoutAServer() throws {
        let catalog = makeCatalog(serverURL: "")
        let file = URL(fileURLWithPath: "/tmp/a.mp3")
        catalog.setLocalTracks(FakeLocalTracks(["a": file]))

        let (_, url) = try #require(catalog.track(forHash: "a"))

        #expect(url == file)
    }
}
