import SwiftUI
import DJukeboxCommon

public class Client {
    public let trackFetcher: TrackFetcher
    public let historyFetcher: HistoryFetcher
    public let server: ServerType

    public init(serverURL: String, password: String, initialQueueType initialQueue: QueueType = .remote) {
        // the server connection for tracks and history 
        self.server = ServerConnection(toUrl: serverURL, withPassword: password)

        // an observable view object for showing lots of track based info
        self.trackFetcher = TrackFetcher(withServer: server)

        // an observable object for keeping the history up to date from the server
        self.historyFetcher = HistoryFetcher(withServer: server, trackFetcher: trackFetcher)

        // which queue do we play to?
        var audioPlayer: AsyncAudioPlayerType!

        let trackFinder = TrackFinder(trackFetcher: trackFetcher,
                                      serverConnection: server)

        /*
         this monstrosity plays the files locally via streaming urls on the server
         */
        let player = NetworkAudioPlayer(trackFinder: trackFinder,
                                        historyWriter: ServerHistoryWriter(server: server))
        trackFetcher.add(queueType: .local,
                         withPlayer: AsyncAudioPlayer(player: player,
                                                      fetcher: trackFetcher,
                                                      history: historyFetcher))
        /*
         an audio player that subclasses the ServerConnection to use apis to manage a server queue
         */
        trackFetcher.add(queueType: .remote,
                         withPlayer: ServerAudioPlayer(toUrl: serverURL, withPassword: password))

        do {
            try trackFetcher.watch(queue: initialQueue)
        } catch {
            print("can't watch queue: \(error)") // XXX handle this better
        }
        
        historyFetcher.refresh()
        trackFetcher.refreshTracks()
        trackFetcher.refreshQueue()
        
        // Create the SwiftUI view that provides the window contents.
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.trackFetcher.refreshQueue()
            self.historyFetcher.refresh()
        }
    }
}
