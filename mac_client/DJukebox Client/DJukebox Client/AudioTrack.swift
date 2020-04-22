import Cocoa

// XXX copied from the server
public class AudioTrack: Decodable, Identifiable, Comparable, Hashable {
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
    
    let Artist: String
    let Album: String?
    let Title: String
    let Filename: String
    let SHA1: String
    let Duration: String?
    let AudioBitrate: String?
    let SampleRate: String?
    let TrackNumber: String?
    let Genre: String?
    let OriginalDate: String?
}

