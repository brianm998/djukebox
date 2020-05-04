import SwiftUI
import DJukeboxCommon

// copied from the server
public class PlayingQueue: Decodable, Identifiable, ObservableObject {
    let tracks: [AudioTrack]
    let playingTrackDuration: TimeInterval?
    let playingTrackPosition: TimeInterval?

    init(tracks: [AudioTrack],
         playingTrackDuration: TimeInterval?,
         playingTrackPosition: TimeInterval?)
    {
        self.tracks = tracks
        self.playingTrackDuration = playingTrackDuration
        self.playingTrackPosition = playingTrackPosition
    }
}

// copied from the server
public class PlayingHistory: Decodable, Identifiable, ObservableObject {
    let plays: [String: [Double]]
    let skips: [String: [Double]]

    init() {
        self.plays = [:]
        self.skips = [:]
    }
    
    init(plays: [String: [Double]], skips: [String: [Double]]) {
        self.plays = plays
        self.skips = skips
    }

    func recentHistory(startingAt startTime: Date) -> PlayingHistory {
        var recentPlays: [String: [Double]] = [:]
        var recentSkips: [String: [Double]] = [:]
        
        for (hash, times) in self.plays {
            let recentTimes = times.filter { startTime.timeIntervalSince1970 < $0 }
            if recentTimes.count > 0 {
                recentPlays[hash] = recentTimes
            }
        }

        for (hash, times) in self.skips {
            let recentTimes = times.filter { startTime.timeIntervalSince1970 < $0 }
            if recentTimes.count > 0 {
                recentSkips[hash] = recentTimes
            }
        }

        return PlayingHistory(plays: recentPlays, skips: recentSkips)
    }
    
    func merge(with historyToMerge: PlayingHistory) -> PlayingHistory {
        var mergedPlays: [String: [Double]] = [:]
        var mergedSkips: [String: [Double]] = [:]

        for (hash, times) in self.plays {
            if historyToMerge.plays[hash] != nil,
               let timesToMerge = historyToMerge.plays[hash]
            {
                let ff = Set(times)
                mergedPlays[hash] = Array(ff.union(timesToMerge))
            } else {
                mergedPlays[hash] = times
            }
        }

        for (hash, times) in historyToMerge.plays {
            if self.plays[hash] == nil {
                mergedPlays[hash] = times
            }
        }

        for (hash, times) in self.skips {
            if historyToMerge.skips[hash] != nil,
               let timesToMerge = historyToMerge.skips[hash]
            {
                let ff = Set(times)
                mergedSkips[hash] = Array(ff.union(timesToMerge))
            } else {
                mergedSkips[hash] = times
            }
        }

        for (hash, times) in historyToMerge.skips {
            if self.skips[hash] == nil {
                mergedSkips[hash] = times
            }
        }
        
        return PlayingHistory(plays: mergedPlays, skips: mergedSkips)
    }
}

// copied from the server
public class AudioTrack: Decodable,
                         Identifiable,
                         Comparable,
                         Hashable,
                         ObservableObject,
                         AudioTrackType
{
    public static func < (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        if lhs.Artist == rhs.Artist {
            // dig in deeper
            if let lhsAlbum = lhs.Album,
               let rhsAlbum = rhs.Album
            {
                if lhsAlbum == rhsAlbum,
                   let lhsTrackNumberStr = lhs.TrackNumber,
                   let rhsTrackNumberStr = rhs.TrackNumber,
                   let lhsTrackNumber = Int(lhsTrackNumberStr),
                   let rhsTrackNumber = Int(rhsTrackNumberStr)
                {
                    return lhsTrackNumber < rhsTrackNumber
                } else {
                    return lhsAlbum < rhsAlbum
                }
            } else {
                return lhs.Title < rhs.Title
            }
        } else {
            return lhs.Artist < rhs.Artist
        }
    }
    
    public static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        return lhs.SHA1 == rhs.SHA1
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SHA1)
    }

    public var timeIntervalString: String {
        let amount = self.timeInterval
        if amount < 60 {
            return "\(Int(amount))s"
        } else {
            let duration = Int(amount)
            let seconds = String(format: "%02d", duration % 60)
            let minutes = duration / 60
            return "\(minutes):\(seconds)"
        }
    }

    public var timeInterval: TimeInterval {
        var ret: TimeInterval = 0
        if let duration = self.Duration {
            // expecting 0:07:11 (approx)
            let values = duration.split(separator: " ")[0].split(separator: ":")
            if values.count == 3,
               let hours = Double(values[0]),
               let minutes = Double(values[1]),
               let seconds = Double(values[2])
            {
                ret += seconds
                ret += minutes * 60
                ret += hours * 60 * 60
            }
        }
        return ret
    }

    public let Artist: String
    public let Album: String?
    public let Title: String
    public let Filename: String
    public let SHA1: String
    public let Duration: String?
    public let AudioBitrate: String?
    public let SampleRate: String?
    public let TrackNumber: String?
    public let Genre: String?
    public let OriginalDate: String?
}

