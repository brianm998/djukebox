import SwiftUI
import DJukeboxCommon

public class Client {
    public var trackFetcher: TrackFetcher
    public var historyFetcher: HistoryFetcher
    public let serverConnection: ServerType

    // the 1s state-save / refresh loop; held so it can be torn down with the client
    private var refreshTimer: Timer?

    deinit {
        refreshTimer?.invalidate()
    }

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
    

    public init(serverURL: String, token: String, initialQueueType initialQueue: PlayingQueueType = .local) {
        // the server connection for tracks and history
        self.serverConnection = ServerConnection(toUrl: serverURL, withToken: token)

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
        // captured locally (not `self`) so the injected lookup doesn't retain the
        // Client; `fetcher` weakly so it isn't retained either. Local playback gets
        // the per-track saved gain PLUS the global master attenuation, matching what
        // the server applies to its own playback.
        let server = serverConnection
        let player = AVDoghouseAudioPlayer(trackFinder: trackFetcher,
                                           historyWriter: ServerHistoryWriter(server: serverConnection),
                                           savedGainForHash: { [weak fetcher] hash, done in
                                               server.savedGain(forHash: hash) { db, _ in
                                                   done((db ?? 0) + (fetcher?.masterGainDB ?? 0))
                                               }
                                           })
        trackFetcher.add(queueType: .local,
                         withPlayer: AsyncAudioPlayer(player: player,
                                                      fetcher: trackFetcher,
                                                      history: historyFetcher))
        /*
         an audio player that subclasses the ServerConnection to use apis to manage a server queue
         */
        trackFetcher.add(queueType: .remote,
                         withPlayer: ServerAudioPlayer(toUrl: serverURL, withToken: token))

        let runtimeState = RuntimeState.saved(defaultPlayingQueue: initialQueue)

        // this allows clients to keep some tracks locally (i.e. offline).
        // Wired up before initialize(): setting useLocalContentOnly there fires
        // refreshTracks() via its didSet, which needs localTracks in place when
        // restoring offline mode. (An explicit refreshTracks() used to follow as
        // a workaround, fetching the whole catalog from the server a second time.)
        let localTracks = LocalTracks(trackFinder: self.trackFetcher)
        trackFetcher.localTracks = localTracks

        trackFetcher.initialize(with: runtimeState)

        // (no historyFetcher.refresh() here: its init already fetched the full
        // history, and the 1s timer below keeps it current incrementally)
        trackFetcher.refreshQueue()
        trackFetcher.refreshMasterGain()

        // Create the SwiftUI view that provides the window contents.
        
        // weak self so the timer doesn't keep this client alive forever; deinit
        // invalidates it, so replacing the client (e.g. on a scan/reconnect) stops it
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.trackFetcher.runtimeState.save()
            self.trackFetcher.refreshQueue()
            self.historyFetcher.refresh()
        }
    }
}
