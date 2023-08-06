import SwiftUI
import DJukeboxCommon

public class Client {
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
    

    public init(serverURL: String, password: String, initialQueueType initialQueue: PlayingQueueType = .local) {
        // the server connection for tracks and history 
        self.serverConnection = ServerConnection(toUrl: serverURL, withPassword: password)

        // an observable view object for showing lots of track based info
        let fetcher = TrackFetcher(withServer: serverConnection)
        self.trackFetcher = fetcher

        // an observable object for keeping the history up to date from the server
        self.historyFetcher = HistoryFetcher(withServer: serverConnection, trackFetcher: fetcher)

        // which queue do we play to?
        var audioPlayer: AsyncAudioPlayerType!

        /*
         plays tracks locally via streaming urls on the server.

         The doghouse treats the AVQueuePlayer like a little dog, only giving it one track a a time
         */
        let player = AVDoghouseAudioPlayer(trackFinder: trackFetcher,
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

        let runtimeState = RuntimeState.saved(defaultPlayingQueue: initialQueue)

        trackFetcher.initialize(with: runtimeState)
        
        // this allows clients to keep some tracks locally (i.e. offline)
        let localTracks = LocalTracks(trackFinder: self.trackFetcher)
        trackFetcher.localTracks = localTracks
        
        historyFetcher.refresh()
        trackFetcher.refreshTracks()
        trackFetcher.refreshQueue()

        // Create the SwiftUI view that provides the window contents.
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.trackFetcher.runtimeState.save()
            self.trackFetcher.refreshQueue()
            self.historyFetcher.refresh()
        }
    }
}
