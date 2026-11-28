import AVFoundation
import Foundation
import Testing
import DJukeboxCommon
@testable import DJukeboxClient

private struct DiscardingHistoryWriter: HistoryWriterType {
    func writePlay(of sha1: String, at date: Date) throws {}
    func writeSkip(of sha1: String, at date: Date) throws {}
}

// These load real AVPlayerItems. The player stays paused, so no audio is played.
@MainActor
struct AVDoghouseFailureTests {
    // ten seconds of silence
    private func writeSilence(to url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80_000))
        buffer.frameLength = buffer.frameCapacity
        try #require(buffer.floatChannelData)[0].update(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @Test func unloadableAndUnknownTracksAreSkipped() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bad = dir.appendingPathComponent("bad.mp3")
        try Data("this is not audio".utf8).write(to: bad)
        let good = dir.appendingPathComponent("good.wav")
        try writeSilence(to: good)

        let catalog = TrackCatalog(serverURL: "", authHeaderValue: "tok")
        catalog.setLocalTracks(FakeLocalTracks(["bad": bad, "good": good]))
        let player = AVDoghouseAudioPlayer(trackFinder: catalog,
                                           historyWriter: DiscardingHistoryWriter())
        player.isPaused = true

        player.play(sha1Hash: "bad")
        player.trackQueue = ["unknown", "good"]

        for _ in 0..<200 where player.playingTrack?.SHA1 != "good" {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(player.playingTrack?.SHA1 == "good")
        #expect(player.trackQueue.isEmpty)
        #expect(player.player.items().count == 1)
    }
}
