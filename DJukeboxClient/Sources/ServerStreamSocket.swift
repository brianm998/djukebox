import Foundation
import DJukeboxCommon

// One frame off the server's /stream WebSocket. Exactly one payload is set,
// selected by `type`. Mirrors the server's StreamFrame. Public: the owner
// (Client) now consumes these directly off ServerStreamSocket.frames instead
// of via internal-only callback closures.
public struct StreamPositionFrame: Decodable, Sendable {
    public let position: TimeInterval?
    public let duration: TimeInterval?
}

public struct StreamFrame: Decodable, Sendable {
    public let type: String
    public let levels: AudioLevels?
    public let queue: PlayingQueue?
    public let position: StreamPositionFrame?
    public let history: PlayingHistory?
}

// Client end of the server's /stream WebSocket: instead of polling /levels,
// /queue and /history, we hold one connection open and receive pushed frames.
// The server only sends while something changes (or, for levels/position, while
// it's actually playing), so an idle connection costs nothing. Owned by Client,
// which routes each frame type to the right consumer (VU monitor, TrackFetcher,
// HistoryFetcher).
//
// Modeled as an actor: connection lifecycle (task/shouldConnect) is confined by
// actor isolation instead of a manual serial DispatchQueue, and frames are
// delivered to the owner via an AsyncStream instead of four @Sendable callbacks.
public actor ServerStreamSocket {
    private let request: URLRequest
    private var task: URLSessionWebSocketTask?
    private var shouldConnect = false

    // The read loop (spawned by connect(), cancelled by disconnect()/deinit).
    // Held so disconnect() can stop it deterministically before tearing down
    // the underlying WebSocket task.
    private var readLoopTask: Task<Void, Never>?

    // Frames are delivered here; the owner (Client) consumes them with
    // `for await`. A "drop the meter to rest" frame (levels: .unavailable) is
    // pushed on disconnect/failure, replacing the old direct onLevels? call.
    // AsyncStream.makeStream() needs macOS 14/iOS 17; the floor here is
    // macOS 13/iOS 16, so build the stream with the older init(_:) instead,
    // capturing its continuation via a local var that the buildingClosure sets
    // synchronously before AsyncStream's initializer returns.
    public nonisolated let frames: AsyncStream<StreamFrame>
    private let continuation: AsyncStream<StreamFrame>.Continuation

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
        var cont: AsyncStream<StreamFrame>.Continuation!
        self.frames = AsyncStream<StreamFrame> { cont = $0 }
        self.continuation = cont
    }

    // Open the connection (idempotent) and keep it open, reconnecting if dropped.
    public func connect() {
        guard !shouldConnect else { return }
        shouldConnect = true
        openIfNeeded()
    }

    // Close the connection and stop reconnecting.
    public func disconnect() {
        shouldConnect = false
        readLoopTask?.cancel()
        readLoopTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation.yield(unavailableFrame)
    }

    // Nonisolated, synchronous teardown for deinit (which can't await an actor
    // method). Fires the same cancellation off without waiting for it to finish;
    // Task is Sendable and cancellable from a nonisolated context, so no
    // nonisolated(unsafe) escape hatch is needed (matches PairingMonitor's and
    // PairingClient's deinit in Pairing.swift).
    public nonisolated func disconnectSync() {
        Task { await self.disconnect() }
    }

    deinit {
        continuation.finish()
    }

    private func openIfNeeded() {
        guard shouldConnect, task == nil else { return }
        let t = URLSession.shared.webSocketTask(with: request)
        // The default incoming-message cap is 1 MB; a full playing queue can exceed
        // that, and rejecting a frame tears down the whole connection. Give it ample
        // headroom (history is now pushed incrementally, so frames stay small).
        t.maximumMessageSize = 16 * 1024 * 1024
        task = t
        t.resume()
        readLoopTask = Task { [weak self] in
            await self?.readLoop(on: t)
        }
    }

    // Runs on the actor. Replaces the old recursive `t.receive { }` callback
    // chain with a plain loop over the async receive() API.
    private func readLoop(on t: URLSessionWebSocketTask) async {
        while shouldConnect && task === t {
            do {
                let message = try await t.receive()
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let frame = try? JSONDecoder().decode(StreamFrame.self, from: data) {
                    continuation.yield(frame)
                }
            } catch {
                guard task === t else { return }   // superseded by a newer connection
                task = nil
                continuation.yield(unavailableFrame)   // drop the meter to rest
                if shouldConnect {
                    try? await Task.sleep(for: .seconds(1))
                    guard shouldConnect else { return }
                    openIfNeeded()
                }
                return
            }
        }
    }

    private var unavailableFrame: StreamFrame {
        StreamFrame(type: "levels", levels: .unavailable, queue: nil, position: nil, history: nil)
    }
}
