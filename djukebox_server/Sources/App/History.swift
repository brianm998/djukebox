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

public class History: HistoryType {

    public var plays: [String: [Double]] = [:]
    public var skips: [String: [Double]] = [:]

    var all: PlayingHistory { return PlayingHistory(plays: self.plays, skips: self.skips) }

    public func since(time: Date) -> PlayingHistory {
        var plays: [String: [Double]] = [:]
        var skips: [String: [Double]] = [:]
        for (hash, times) in self.plays {
            var newTimes: [Double] = []
            for hashTime in times {
                let date = Date(timeIntervalSince1970: hashTime)
                if time < date { newTimes.append(hashTime) }
            }
            if newTimes.count > 0 { plays[hash] = newTimes }
        }
        for (hash, times) in self.skips {
            var newTimes: [Double] = []
            for hashTime in times {
                let date = Date(timeIntervalSince1970: hashTime)
                if time < date { newTimes.append(hashTime) }
            }
            if newTimes.count > 0 { skips[hash] = newTimes }
        }
        return PlayingHistory(plays: plays, skips: skips)
    }
    
    public func find(atFilePath path: String) {
        find(at: URL(fileURLWithPath: path))
    }

    public func hasPlay(for hash: String) -> Bool {
        return plays[hash] != nil
    }
    
    public func hasSkip(for hash: String) -> Bool {
        return skips[hash] != nil
    }
    
    public func recordSkip(of hash: String, at time: Double) {
        if skips[hash] == nil {
            skips[hash] = [time]
        } else if var list = skips[hash] {
            list.append(time)
        } else {
            Log.d("DOH")
        }
    }
    
    public func recordSkip(of hash: String, at time: Date) {
        self.recordSkip(of: hash, at: time.timeIntervalSince1970)
    }

    public func recordPlay(of hash: String, at time: Double) {
        if plays[hash] == nil {
            Log.d("fuck1")
            plays[hash] = [time]
        } else if var list = plays[hash] {
            Log.d("fuck2")
            list.append(time)
        } else {
            Log.d("DOH")
        }
        Log.d("record play plays \(plays)")
    }
    
    public func recordPlay(of hash: String, at time: Date) {
        self.recordPlay(of: hash, at: time.timeIntervalSince1970)
    }

    fileprivate func find(at url: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for url in urls {
                if url.absoluteString.hasSuffix(".txt") {
                    let string = try String(contentsOf: url)
                    let lines = string.split { $0.isNewline }
                    for line in lines {
                        Log.d("line \(line)")
                        let data = line.split { $0 == "," }
                        if data.count == 3,
                           let time = Double(data[1])
                        {
                            let hash = String(data[0])
                            let played_fully = data[2]
                            if played_fully == "1" {
                                self.recordPlay(of: hash, at: time)
                            } else if played_fully == "0" {
                                self.recordSkip(of: hash, at: time)
                            } else {
                                Log.d("bad played_fully \(played_fully)")
                            }
                            Log.d("YES: line \(line)")
                        } else {
                            Log.d("FUCK: line \(line)")
                        }
                    }
                }
            }
        } catch {
            Log.e("DOH \(url) \(error)")
        }
    }    
}

