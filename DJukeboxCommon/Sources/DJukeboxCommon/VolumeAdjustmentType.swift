import Foundation

// The three scopes a volume adjustment can be attached to. A track's effective
// gain is resolved with precedence track > album > artist (see
// VolumeAdjustmentSource); the most specific match wins.
//
// Note on keys: what the clients browse as an "artist" is the `Artist` field
// (renamed from `Band`), and an album is identified by (Artist, Album) — not
// the separate per-track `Credit` field (renamed from `Artist`).
// The server assembles the storage keys from those fields.
public enum VolumeScope: String, Sendable, Codable {
    case track
    case album
    case artist
}

// Supplies the effective playback gain, in decibels, for the track with a given
// hash (0 dB = unchanged / unity, positive = boost). The concrete implementation
// lives in the server, backed by the SQLite `volume_adjustment` table, and is
// injected into the audio players exactly like HistoryWriterType / TrackFinderType.
// A nil source — or any lookup error — means "no adjustment", i.e. 0 dB.
public protocol VolumeAdjustmentSource: Sendable {
    func gainDecibels(forHash sha1: String) -> Double
}
