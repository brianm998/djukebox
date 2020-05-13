import Foundation
import DJukeboxCommon

public class RuntimeState: LocalCache, Encodable, Decodable {
    /*
     State we need to keep:
      - paused / playing state
      - offline mode
      - what playing queue 
      - currently playing song, including playing position
      */

    var isPaused: Bool
    var isOffline: Bool
    var playingQueue: PlayingQueueType
    var playingTrack: String?
    var playingTrackPosition: Double?
    var pendingTracks: [String]

    public init(isPaused: Bool = false,
                isOffline: Bool = false,
                playingQueue: PlayingQueueType,
                playingTrack: String? = nil,
                playingTrackPosition: Double? = nil,
                pendingTracks: [String] = [])
    {

        self.isPaused = isPaused
        self.isOffline = isOffline
        self.playingQueue = playingQueue
        self.playingTrack = playingTrack
        self.playingTrackPosition = playingTrackPosition
        self.pendingTracks = pendingTracks
    }
    
    private static var url: URL? {
        return LocalCache.urlForLibrary(appending: ["State"])?
          .appendingPathComponent("RuntimeState")
          .appendingPathExtension("json")
    }

    func save() {
        let encoder = JSONEncoder()
        if let url = RuntimeState.url {
            do {
                let jsonData = try encoder.encode(self)
                try jsonData.write(to: url)
            } catch {
                Log.e("error: \(error)")
            }
        } else {
            Log.e()
        }
    }

    static func saved(defaultPlayingQueue: PlayingQueueType = .local) -> RuntimeState {
        if let url = RuntimeState.url {
            do {
                let ret = try JSONDecoder().decode(RuntimeState.self, from: try Data(contentsOf: url))
                //Log.w(ret)
                return ret
            } catch {
                Log.i("error: \(error)")
            }
        }

        // if we can't load from flash, use the default
        return RuntimeState(playingQueue: defaultPlayingQueue)
    }
}


