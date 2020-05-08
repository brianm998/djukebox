import SwiftUI
import DJukeboxCommon

public class Client: ObservableObject {
    public var trackFetcher: TrackFetcher
    public var historyFetcher: HistoryFetcher
    public let serverConnection: ServerType

    public func copy() -> Client {
        return Client(trackFetcher: self.trackFetcher,
                      historyFetcher: self.historyFetcher,
                      serverConnection: self.serverConnection)
    }

    fileprivate init(trackFetcher: TrackFetcher,
                     historyFetcher: HistoryFetcher,
                     serverConnection: ServerType)
    {
        self.trackFetcher = trackFetcher
        self.historyFetcher = historyFetcher
        self.serverConnection = serverConnection
    }
    
    public init(serverURL: String, password: String, initialQueueType initialQueue: QueueType = .remote) {
        // the server connection for tracks and history 
        self.serverConnection = ServerConnection(toUrl: serverURL, withPassword: password)

        let fetcher = TrackFetcher(withServer: serverConnection)
        
        // an observable view object for showing lots of track based info
        self.trackFetcher = fetcher

        // an observable object for keeping the history up to date from the server
        self.historyFetcher = HistoryFetcher(withServer: serverConnection, trackFetcher: fetcher)

        // which queue do we play to?
        var audioPlayer: AsyncAudioPlayerType!

        let trackFinder = TrackFinder(trackFetcher: trackFetcher,
                                      serverConnection: serverConnection)

        /*
         this monstrosity plays the files locally via streaming urls on the server
         */
        let player = NetworkAudioPlayer(trackFinder: trackFinder,
                                        historyWriter: ServerHistoryWriter(server: serverConnection))
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
