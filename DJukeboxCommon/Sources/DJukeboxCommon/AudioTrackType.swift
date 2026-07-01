import Foundation

// Sendable: track metadata is immutable value data; both conformers (the client
// and server AudioTrack types) are already Sendable. This lets tracks cross the
// audio-player / networking callback boundaries safely.
public protocol AudioTrackType: Sendable {
    var Artist: String { get }
    var Album: String? { get }
    var Title: String { get }
    var Filename: String { get }
    var SHA1: String { get }
    var Duration: String? { get }
    var timeInterval: Double? { get }
    var AudioBitrate: String? { get }
    var SampleRate: String? { get }
    var TrackNumber: String? { get }
    var Genre: String? { get }
    var OriginalDate: String? { get }
}
