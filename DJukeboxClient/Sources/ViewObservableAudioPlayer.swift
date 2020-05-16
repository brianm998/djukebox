import Foundation

public class ViewObservableAudioPlayer: ObservableObject {
    public var player: AsyncAudioPlayerType?

    public init(player: AsyncAudioPlayerType? = nil) {
        self.player = player
    }
    
    public var isPaused: Bool { return player?.isPaused ?? false }
}

