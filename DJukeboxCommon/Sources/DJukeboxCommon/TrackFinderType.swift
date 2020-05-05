import Foundation

public protocol TrackFinderType {
    func track(forHash sha1Hash: String) -> (AudioTrackType, URL)?
    //func filePath(forHash sha1Hash: String) -> String?
    func audioTrack(forHash sha1Hash: String) -> AudioTrackType?
    //func find(atFilePath path: String)
//    var tracks: [String: (AudioTrackType, [URL])] { get }
  //  func tracks(forArtist: String) -> [String: (AudioTrackType, [URL])]
}

