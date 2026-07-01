import Foundation

// @unchecked Sendable: thin observable wrapper holding the current player; `player`
// is swapped on the main thread when the queue type changes. See the client
// concurrency note in AsyncAudioPlayer.
public class ViewObservableAudioPlayer: ObservableObject, @unchecked Sendable {
    public var player: AsyncAudioPlayerType?

    public init(player: AsyncAudioPlayerType? = nil) {
        self.player = player
    }
    
    public var isPaused: Bool { return player?.isPaused ?? false }
}

