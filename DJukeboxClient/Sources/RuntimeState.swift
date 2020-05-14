import Foundation
import DJukeboxCommon

// without these, optional doubles fuck up both the json encoder and decoder
fileprivate let positiveInfinity = "+Infinity"
fileprivate let negativeInfinity = "-Infinity"
fileprivate let NaN = "NaN"

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

    fileprivate static var encoder: JSONEncoder {
        let ret = JSONEncoder()
        ret.nonConformingFloatEncodingStrategy =
          .convertToString(positiveInfinity: positiveInfinity,
                           negativeInfinity: negativeInfinity,
                           nan: NaN)
        return ret
    }
    
    fileprivate static var decoder: JSONDecoder {
        let ret = JSONDecoder()
        ret.nonConformingFloatDecodingStrategy =
          .convertFromString(
            positiveInfinity: positiveInfinity,
            negativeInfinity: negativeInfinity,
            nan: NaN)
        return ret
    }
    
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
        if let url = RuntimeState.url {
            do {
                let jsonData = try RuntimeState.encoder.encode(self)
                Log.d(String(data: jsonData, encoding: .utf8))
                try jsonData.write(to: url)
            } catch {
                Log.i(self)
                Log.e("error: \(error)")
            }
        } else {
            Log.e()
        }
    }

    static func saved(defaultPlayingQueue: PlayingQueueType = .local) -> RuntimeState {
        if let url = RuntimeState.url {
            do {
                if let ret = try? RuntimeState.decoder.decode(RuntimeState.self, from: try Data(contentsOf: url)) {
                    // one extra step required to keep swift Double? working
                    if ret.playingTrackPosition?.isNaN ?? false { ret.playingTrackPosition = nil }
                    return ret
                }
            } catch {
                Log.i("error: \(error)")
                // remove any badly written file here
                try? FileManager.default.removeItem(atPath: url.path)
            }
        }

        Log.i("failed to load a saved runtime configuration")
        
        // if we can't load from flash, use the default
        return RuntimeState(playingQueue: defaultPlayingQueue)
    }
}


