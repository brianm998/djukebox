import Foundation

// Sendable: track metadata is immutable value data; both conformers (the client
// and server AudioTrack types) are already Sendable. This lets tracks cross the
// audio-player / networking callback boundaries safely.
public protocol AudioTrackType: Sendable {
    var Credit: String { get }
    var Title: String { get }
    var SHA1: String { get }
    var timeInterval: Double? { get }
}
