import Foundation
import DJukeboxCommon

// One frame off the server's /stream WebSocket. Exactly one payload is set,
// selected by `type`. Mirrors the server's StreamFrame.
struct StreamPositionFrame: Decodable, Sendable {
    let position: TimeInterval?
    let duration: TimeInterval?
}

struct StreamFrame: Decodable, Sendable {
    let type: String
    let levels: AudioLevels?
    let queue: PlayingQueue?
    let position: StreamPositionFrame?
    let history: PlayingHistory?
}

// Client end of the server's /stream WebSocket: instead of polling /levels,
// /queue and /history, we hold one connection open and receive pushed frames.
// The server only sends while something changes (or, for levels/position, while
// it's actually playing), so an idle connection costs nothing. Owned by Client,
// which routes each frame type to the right consumer (VU monitor, TrackFetcher,
// HistoryFetcher).
//
// @unchecked Sendable: the connection lifecycle (task/shouldConnect) is confined
// to the private serial queue; frames are delivered via @Sendable callbacks.
public final class ServerStreamSocket: @unchecked Sendable {
    private let request: URLRequest
    private let queue = DispatchQueue(label: "djukebox-stream-socket")
    private var task: URLSessionWebSocketTask?
    private var shouldConnect = false

    // Set by the owner (Client) to route frames. levels is invoked on the receive
    // thread (its consumer is thread-safe); queue/position/history are invoked on
    // the main thread.
    public var onLevels: (@Sendable (AudioLevels) -> Void)?
    public var onQueue: (@Sendable (PlayingQueue) -> Void)?
    public var onPosition: (@Sendable (TimeInterval?, TimeInterval?) -> Void)?
    public var onHistory: (@Sendable (PlayingHistory) -> Void)?

    // Builds the ws(s):// URL from the http(s):// server URL. Fails (→ nil) when
    // there's no real host — e.g. the offline/local-only client.
    public init?(baseURL: String, token: String) {
        guard var comps = URLComponents(string: baseURL),
              let host = comps.host, !host.isEmpty else { return nil }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        let base = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = base + "/stream"
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        self.request = req
    }

    // Open the connection (idempotent) and keep it open, reconnecting if dropped.
    public func connect() {
        queue.async {
            self.shouldConnect = true
            self.openIfNeeded()
        }
    }

    // Close the connection and stop reconnecting.
    public func disconnect() {
        queue.async {
            self.shouldConnect = false
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.onLevels?(.unavailable)
        }
    }

    // must run on `queue`
    private func openIfNeeded() {
        guard shouldConnect, task == nil else { return }
        let t = URLSession.shared.webSocketTask(with: request)
        // The default incoming-message cap is 1 MB; a full playing queue can exceed
        // that, and rejecting a frame tears down the whole connection. Give it ample
        // headroom (history is now pushed incrementally, so frames stay small).
        t.maximumMessageSize = 16 * 1024 * 1024
        task = t
        t.resume()
        listen(on: t)
    }

    private func listen(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let frame = try? JSONDecoder().decode(StreamFrame.self, from: data) {
                    self.deliver(frame)
                }
                self.listen(on: t)   // re-arm for the next frame
            case .failure:
                self.queue.async {
                    guard self.task === t else { return }
                    self.task = nil
                    self.onLevels?(.unavailable)   // drop the meter to rest
                    if self.shouldConnect {
                        self.queue.asyncAfter(deadline: .now() + 1) { self.openIfNeeded() }
                    }
                }
            }
        }
    }

    // Route one frame. Levels go straight through (their consumer is thread-safe);
    // queue/position/history touch @Published state, so hop to the main thread.
    // Captures only Sendable locals (not self) so it's clean under Swift 6.
    private func deliver(_ frame: StreamFrame) {
        if let levels = frame.levels { onLevels?(levels) }
        guard frame.queue != nil || frame.position != nil || frame.history != nil else { return }
        let queueFrame = frame.queue
        let positionFrame = frame.position
        let historyFrame = frame.history
        let onQueue = self.onQueue
        let onPosition = self.onPosition
        let onHistory = self.onHistory
        DispatchQueue.main.async {
            if let queueFrame { onQueue?(queueFrame) }
            if let positionFrame { onPosition?(positionFrame.position, positionFrame.duration) }
            if let historyFrame { onHistory?(historyFrame) }
        }
    }
}
