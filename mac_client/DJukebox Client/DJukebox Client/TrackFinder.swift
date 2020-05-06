import Foundation
import DJukeboxCommon

public class TrackFinder: TrackFinderType {
    
    public var tracks: [String : (AudioTrackType, [URL])]
    let trackFetcher: TrackFetcher
    let serverConnection: ServerType

    init(trackFetcher: TrackFetcher, serverConnection: ServerType) {
        self.trackFetcher = trackFetcher
        self.serverConnection = serverConnection
        self.tracks = [:]
    }
    
    public func track(forHash sha1Hash: String) -> (AudioTrackType, URL)? {
        if let track = trackFetcher.trackMap[sha1Hash],
           let url = URL(string: "\(serverURL)/stream/\(serverConnection.authHeaderValue)/\(sha1Hash)")
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
