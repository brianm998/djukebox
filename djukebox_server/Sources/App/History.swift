import Vapor
import DJukeboxCommon

public protocol HistoryType {
    var plays: [String: [Double]] { get }
    var skips: [String: [Double]] { get }

    func recordPlay(of hash: String, at time: Date)
    func recordSkip(of hash: String, at time: Date)
    func recordPlay(of hash: String, at time: Double)
    func recordSkip(of hash: String, at time: Double)
    func find(atFilePath path: String)
}

// In-RAM fast read path over the play history. The database (JukeboxDatabase)
// is the persistent store of record; this mirror is loaded from it at startup
// (`load(plays:skips:)`) and kept in sync write-through. All access is guarded
// by a lock because the dictionaries are read by request handlers on event-loop
// threads while the audio player writes from its own thread.
public class History: HistoryType {

    private var _plays: [String: [Double]] = [:]
    private var _skips: [String: [Double]] = [:]
    private let lock = NSLock()

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    public var plays: [String: [Double]] { withLock { _plays } }
    public var skips: [String: [Double]] { withLock { _skips } }

    var all: PlayingHistory { withLock { PlayingHistory(plays: _plays, skips: _skips) } }

    /// Replace the entire in-RAM history (used to load from the database at startup).
    public func load(plays: [String: [Double]], skips: [String: [Double]]) {
        withLock {
            _plays = plays
            _skips = skips
        }
    }

    public func since(time: Date) -> PlayingHistory {
        withLock {
            var plays: [String: [Double]] = [:]
            var skips: [String: [Double]] = [:]
            for (hash, times) in _plays {
                let newTimes = times.filter { time < Date(timeIntervalSince1970: $0) }
                if newTimes.count > 0 { plays[hash] = newTimes }
            }
            for (hash, times) in _skips {
                let newTimes = times.filter { time < Date(timeIntervalSince1970: $0) }
                if newTimes.count > 0 { skips[hash] = newTimes }
            }
            return PlayingHistory(plays: plays, skips: skips)
        }
    }

    public func hasPlay(for hash: String) -> Bool { withLock { _plays[hash] != nil } }
    public func hasSkip(for hash: String) -> Bool { withLock { _skips[hash] != nil } }

    public func recordSkip(of hash: String, at time: Double) {
        withLock { _skips[hash, default: []].append(time) }
    }

    public func recordSkip(of hash: String, at time: Date) {
        self.recordSkip(of: hash, at: time.timeIntervalSince1970)
    }

    public func recordPlay(of hash: String, at time: Double) {
        withLock { _plays[hash, default: []].append(time) }
    }

    public func recordPlay(of hash: String, at time: Date) {
        self.recordPlay(of: hash, at: time.timeIntervalSince1970)
    }

    public func find(atFilePath path: String) {
        for event in History.legacyEvents(inDirectory: path) {
            if event.fullyPlayed {
                self.recordPlay(of: event.sha1, at: event.time)
            } else {
                self.recordSkip(of: event.sha1, at: event.time)
            }
        }
    }

    /// Parses the legacy on-disk history format — one `sha1,unixTime,flag` per
    /// line across `history_*.txt` files (flag `1` = play, `0` = skip) — into a
    /// flat list of events. Used for the one-time import into the database.
    /// Returns an empty list (rather than throwing) when the directory is absent.
    public static func legacyEvents(inDirectory path: String)
      -> [(sha1: String, time: Double, fullyPlayed: Bool)]
    {
        var events: [(sha1: String, time: Double, fullyPlayed: Bool)] = []
        let dir = URL(fileURLWithPath: path)
        guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else {
            return events
        }
        for url in urls {
            guard url.pathExtension == "txt" else { continue }
            guard let string = try? String(contentsOf: url) else { continue }
            for line in string.split(whereSeparator: { $0.isNewline }) {
                let data = line.split(separator: ",")
                guard data.count == 3, let time = Double(data[1]) else { continue }
                let sha1 = String(data[0])
                let flag = String(data[2])
                if flag == "1" {
                    events.append((sha1: sha1, time: time, fullyPlayed: true))
                } else if flag == "0" {
                    events.append((sha1: sha1, time: time, fullyPlayed: false))
                }
            }
        }
        return events
    }
}
