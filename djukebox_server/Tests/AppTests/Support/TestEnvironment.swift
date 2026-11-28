@testable import App
import Foundation

/// Points the server's database, music and history paths at a temporary
/// directory holding a few fixture tracks.
///
/// The server reads those paths into lazily-initialised globals, once per
/// process, so `activate()` must run before any test touches them.
enum TestEnvironment {
    static let trackA = String(repeating: "a", count: 40)
    static let trackB = String(repeating: "b", count: 40)
    static let trackC = String(repeating: "c", count: 40)

    private static let temporaryDirectory =
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).path + "/"

    private static let root = temporaryDirectory + "djukebox-tests-\(UUID().uuidString)"

    // a static `let` initialiser runs exactly once
    private static let prepared: Void = {
        let fm = FileManager.default
        let music = root + "/music"
        let historyPath = root + "/history"
        do {
            try fm.createDirectory(atPath: music, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: historyPath, withIntermediateDirectories: true)
            for (hash, title) in [(trackA, "A"), (trackB, "B"), (trackC, "C")] {
                let filename = "\(title).mp3"
                // sidecar keys as mp3.pl writes them
                let sidecar = ["Artist": "Queen", "Band": "Queen", "Title": title,
                               "Filename": filename, "SHA1": hash]
                try JSONEncoder().encode(sidecar)
                  .write(to: URL(fileURLWithPath: "\(music)/\(title).json"))
                try Data().write(to: URL(fileURLWithPath: "\(music)/\(filename)"))
            }
        } catch {
            fatalError("could not create test fixtures under \(root): \(error)")
        }
        setenv("DJUKEBOX_DB_PATH", root + "/db.sqlite", 1)
        setenv("DJUKEBOX_MUSIC_DIR", music, 1)
        setenv("DJUKEBOX_HISTORY_DIR", historyPath, 1)
        unsetenv("DJUKEBOX_REQUIRE_MUSIC_DIR")
    }()

    static func activate() {
        _ = prepared
        // trap rather than fail: carrying on could touch the real library
        for path in [databasePath, musicDir, historyDir] {
            precondition(path.hasPrefix(root + "/") && path.hasPrefix(temporaryDirectory),
                         "test would use a non-temporary path: \(path)")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
