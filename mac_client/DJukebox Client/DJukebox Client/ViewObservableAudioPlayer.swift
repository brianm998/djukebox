import Foundation

class ViewObservableAudioPlayer: ObservableObject {
    let player: AsyncAudioPlayerType

    public init(player: AsyncAudioPlayerType) {
        self.player = player
    }
    
    var isPaused: Bool { return player.isPaused }
}

