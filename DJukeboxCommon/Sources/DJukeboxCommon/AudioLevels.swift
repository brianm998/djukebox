import Foundation

// A snapshot of the audio player's current per-channel output loudness, used to
// drive the clients' vacuum-tube VU meter. `left` / `right` are 0...1 (0 =
// silence, 1 = full scale).
//
// `available` distinguishes "playing, but silent right now" (available = true,
// levels 0) from "this player can't measure its own output" (available = false):
// the Linux server plays through an ffplay subprocess whose samples never pass
// through this process, so it reports `.unavailable` and clients render the meter
// at rest rather than trusting the zeros. Shared by both the server (encodes) and
// the client (decodes), so the wire shape stays in one place.
public struct AudioLevels: Codable, Sendable, Equatable {
    public var left: Float
    public var right: Float
    public var available: Bool

    public init(left: Float, right: Float, available: Bool = true) {
        self.left = left
        self.right = right
        self.available = available
    }

    /// The player has no way to measure its output.
    public static let unavailable = AudioLevels(left: 0, right: 0, available: false)
    /// Metering works, but there is no sound right now.
    public static let silent = AudioLevels(left: 0, right: 0, available: true)
}
