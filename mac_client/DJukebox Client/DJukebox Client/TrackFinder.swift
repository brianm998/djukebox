import Foundation
import DJukeboxCommon

public class TrackFinder: TrackFinderType {
    
    public var tracks: [String : (AudioTrackType, [URL])]
    
    let trackFetcher: TrackFetcher

    init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
        self.tracks = [:]
    }
    
    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let track = trackFetcher.trackMap[sha1Hash],
           let url = URL(string: "\(serverURL)/stream/\(sha1Hash)") // XXX need auth still with URLRequest
        {
            return (track, url)
        }
        return nil
    }
    
    public func audioTrack(forHash sha1Hash: String) -> AudioTrackType? {
        if let track = trackFetcher.trackMap[sha1Hash] {
            return track
        }
        return nil
    }
}
