import SwiftUI
import DJukeboxCommon

public class Client {
    public var trackFetcher: TrackFetcher
    public var historyFetcher: HistoryFetcher
    public let serverConnection: ServerType

    // Drives the vacuum-tube VU meter (per-channel output levels). Shared across a
    // window's browse-client copies so every window's meter shows the same thing.
    public let levelMonitor: AudioLevelMonitor

    // The single push connection (/stream) that feeds levels/queue/position/history,
    // replacing the polling that used to run every second. Owned by the connected
    // client only (like refreshTimer); copies share the fetchers it routes to but
    // do NOT own the socket, so a closing browse window can't tear down the stream.
    private let streamSocket: ServerStreamSocket?

    // the 1s state-save / refresh loop; held so it can be torn down with the client
    private var refreshTimer: Timer?

    deinit {
        refreshTimer?.invalidate()
        streamSocket?.disconnect()
    }

    public func copy() -> Client {
        return Client(trackFetcher: self.trackFetcher,
                      historyFetcher: self.historyFetcher,
                      serverConnection: self.serverConnection,
                      levelMonitor: self.levelMonitor)
    }

    fileprivate init(trackFetcher: TrackFetcher,
                     historyFetcher: HistoryFetcher,
                     serverConnection: ServerType,
                     levelMonitor: AudioLevelMonitor)
    {
        self.trackFetcher = trackFetcher
        self.historyFetcher = historyFetcher
        self.serverConnection = serverConnection
        self.levelMonitor = levelMonitor
        self.streamSocket = nil   // copies don't own the stream
    }
    

    @MainActor
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
        // Shared VU-meter sink: the local player's gain taps write per-channel
        // output levels here, and the monitor below reads them.
        let levelMeter = AudioLevelMeter()

        let server = serverConnection
        let player = AVDoghouseAudioPlayer(trackFinder: trackFetcher,
                                           historyWriter: ServerHistoryWriter(server: serverConnection),
                                           savedGainForHash: { [weak fetcher] hash, done in
                                               // `done` isn't @Sendable, so it can't be captured
                                               // directly by the Task below; box it the same way
                                               // ServerConnection's pre-F07 helpers did. Resolve the
                                               // weak `fetcher` to an immutable value up front too --
                                               // capturing the weak var itself across the Task
                                               // boundary trips the same sending-closure diagnostic.
                                               let doneBox = UncheckedSendableBox(done)
                                               let currentMasterGainDB = fetcher?.masterGainDB ?? 0
                                               Task {
                                                   let db = try? await server.savedGain(forHash: hash)
                                                   doneBox.value((db ?? 0) + currentMasterGainDB)
                                               }
                                           },
                                           levelMeter: levelMeter)
        trackFetcher.add(queueType: .local,
                         withPlayer: AsyncAudioPlayer(player: player,
                                                      fetcher: trackFetcher,
                                                      history: historyFetcher))
        /*
         an audio player that subclasses the ServerConnection to use apis to manage a server queue
         */
        trackFetcher.add(queueType: .remote,
                         withPlayer: ServerAudioPlayer(toUrl: serverURL, withToken: token))

        // Drives the VU meter: reads the local tap's meter for local playback, or
        // the levels pushed over /stream for remote playback (it consults
        // trackFetcher for the active queue and paused state).
        let monitor = AudioLevelMonitor(localMeter: levelMeter, trackFetcher: trackFetcher)
        self.levelMonitor = monitor

        // Open the single push connection and route each frame type. The server
        // pushes only on change (or while playing), so this replaces the per-second
        // polling of /levels, /queue and /history. Consumers are captured weakly;
        // the socket is owned here.
        let history = historyFetcher
        let socket = ServerStreamSocket(baseURL: serverURL, token: token)
        self.streamSocket = socket
        socket?.onLevels = { [weak monitor] levels in monitor?.ingestRemoteLevels(levels) }
        socket?.onQueue = { [weak fetcher] queue in
            // The server's queue is only what we display in REMOTE mode; in local
            // mode the on-device player owns the queue, so ignore server pushes.
            guard let fetcher = fetcher, fetcher.queueType == .remote else { return }
            fetcher.update(playingQueue: queue)
        }
        socket?.onPosition = { [weak fetcher] position, duration in
            guard let fetcher = fetcher, fetcher.queueType == .remote else { return }
            fetcher.updateProgress(position: position, duration: duration)
        }
        socket?.onHistory = { [weak history] pushed in
            Task { @MainActor in history?.ingest(pushed) }
        }
        socket?.connect()

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
        // history once, and the /stream push keeps it current thereafter)
        trackFetcher.refreshQueue()
        trackFetcher.refreshMasterGain()

        // Create the SwiftUI view that provides the window contents.

        // weak self so the timer doesn't keep this client alive forever; deinit
        // invalidates it, so replacing the client (e.g. on a scan/reconnect) stops it.
        // The remote queue and the history now arrive over /stream (pushed), so this
        // only saves runtime state and refreshes the LOCAL queue — a purely on-device
        // computation (no network) that advances the local-playback progress bar.
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.trackFetcher.runtimeState.save()
            if self.trackFetcher.queueType == .local {
                self.trackFetcher.refreshQueue()
            }
        }
    }
}
