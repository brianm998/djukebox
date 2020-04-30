import Vapor

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
    
    public func find(atFilePath path: String) {
        find(at: URL(fileURLWithPath: path))
    }

    public func recordSkip(of hash: String, at time: Double) {
        if skips[hash] == nil {
            skips[hash] = [time]
        } else if var list = skips[hash] {
            list.append(time)
        } else {
            print("DOH")
        }
    }
    
    public func recordSkip(of hash: String, at time: Date) {
        self.recordSkip(of: hash, at: time.timeIntervalSince1970)
    }

    public func recordPlay(of hash: String, at time: Double) {
        if plays[hash] == nil {
            print("fuck1")
            plays[hash] = [time]
        } else if var list = plays[hash] {
            print("fuck2")
            list.append(time)
        } else {
            print("DOH")
        }
        print("record play plays \(plays)")
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
                        print("line \(line)")
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
                                print("bad played_fully \(played_fully)")
                            }
                            print("YES: line \(line)")
                        } else {
                            print("FUCK: line \(line)")
                        }
                    }
                }
            }
        } catch {
            print("DOH \(url) \(error)")
        }
    }    
}

