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

    // Consumes streamSocket.frames with `for await`, routing each frame to the
    // right consumer. Held so deinit can cancel it synchronously (deinit is
    // nonisolated and can't await); Task is Sendable, so this needs no
    // nonisolated(unsafe) escape hatch (same pattern as Pairing.swift).
    private var streamTask: Task<Void, Never>?

    // the 1s state-save / refresh loop; held so it can be torn down with the client
    private var refreshTimer: Timer?

    deinit {
        refreshTimer?.invalidate()
        streamTask?.cancel()
        streamSocket?.disconnectSync()
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
        let player = AVDoghouseAudioPlayer(trackFinder: trackFetcher.catalog,
                                           historyWriter: ServerHistoryWriter(server: serverConnection),
                                           savedGainForHash: { [weak fetcher] hash in
                                               // Called from AVDoghouseAudioPlayer's own Task (it's
                                               // non-isolated, so it awaits us rather than reading
                                               // fetcher.masterGainDB, which is @MainActor, F30).
                                               let currentMasterGainDB = await MainActor.run { fetcher?.masterGainDB ?? 0 }
                                               let db = try? await server.savedGain(forHash: hash)
                                               return (db ?? 0) + currentMasterGainDB
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
        //
        // All four consumers are safe to call from this single @MainActor Task:
        // ingestRemoteLevels only writes into a lock-guarded value (no @Published
        // touch, so the old "levels on the receive thread" fast path was never
        // load-bearing — the lock already made it thread-safe from anywhere);
        // TrackFetcher.update(playingQueue:)/updateProgress hop to main internally;
        // and HistoryFetcher is now @MainActor (F27), so being on the main actor
        // here is what makes ingest(_:) callable at all. Unifying onto one stream
        // consumed on the main actor is therefore strictly simpler, not a behavior
        // change for any of the three.
        let history = historyFetcher
        let socket = ServerStreamSocket(baseURL: serverURL, token: token)
        self.streamSocket = socket
        if let socket {
            self.streamTask = Task { @MainActor [weak monitor, weak fetcher, weak history] in
                await socket.connect()
                for await frame in socket.frames {
                    if let levels = frame.levels {
                        monitor?.ingestRemoteLevels(levels)
                    }
                    if let queueFrame = frame.queue,
                       let fetcher, fetcher.queueType == .remote {
                        // The server's queue is only what we display in REMOTE mode;
                        // in local mode the on-device player owns the queue, so
                        // ignore server pushes.
                        fetcher.update(playingQueue: queueFrame)
                    }
                    if let positionFrame = frame.position,
                       let fetcher, fetcher.queueType == .remote {
                        fetcher.updateProgress(position: positionFrame.position, duration: positionFrame.duration)
                    }
                    if let historyFrame = frame.history {
                        history?.ingest(historyFrame)
                    }
                }
            }
        }

        let runtimeState = RuntimeState.saved(defaultPlayingQueue: initialQueue)

        // this allows clients to keep some tracks locally (i.e. offline).
        // Wired up before initialize(): setting useLocalContentOnly there fires
        // refreshTracks() via its didSet, which needs localTracks in place when
        // restoring offline mode. (An explicit refreshTracks() used to follow as
        // a workaround, fetching the whole catalog from the server a second time.)
        let localTracks = LocalTracks(trackFinder: self.trackFetcher.catalog)
        localTracks.fetcher = fetcher
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
        // Timer's closure is @Sendable/non-isolated, but trackFetcher is @MainActor
        // (F30) now, so hop over explicitly rather than touching it directly.
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.trackFetcher.runtimeState.save()
                if self.trackFetcher.queueType == .local {
                    self.trackFetcher.refreshQueue()
                }
            }
        }
    }
}
