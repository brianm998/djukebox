import Foundation

// @MainActor: thin observable wrapper holding the current player; AsyncAudioPlayerType
// is @MainActor (F30), so this follows. See the client concurrency note in
// AsyncAudioPlayer.
@MainActor
public class ViewObservableAudioPlayer: ObservableObject {
    public var player: AsyncAudioPlayerType?

    public init(player: AsyncAudioPlayerType? = nil) {
        self.player = player
    }
    
    public var isPaused: Bool { return player?.isPaused ?? false }
}

