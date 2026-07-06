import Vapor
import NIOCore
import DJukeboxCommon

// Pushes state to one connected /stream WebSocket client, replacing the old
// polling of /levels, /queue and /history. On a 50 ms tick it sends:
//   • levels   — every tick while playing (~20 Hz); one silent frame on stop.
//   • queue    — whenever the playing queue changes (membership / pause).
//   • position — a couple of times a second while playing, so the client's
//                progress bar advances between (rarer) queue frames.
//   • history  — whenever a play/skip is recorded (History.version changes).
// While idle (paused / nothing playing / no changes) it sends nothing, so an
// idle connection generates no traffic. Builds that can't meter their output
// (Linux subprocess) just never send levels.
//
// @unchecked Sendable: all state is only touched from the socket's own event
// loop — scheduleRepeatedTask runs there, and start/stop are called from the
// upgrade handler / onClose on that same loop.
final class StreamSession: @unchecked Sendable {
    private let ws: WebSocket
    private var task: RepeatedTask?
    private let encoder = JSONEncoder()

    private var tickCount = 0
    private var sentSilentLevels = false
    private var lastQueueSignature = ""
    private var lastHistoryVersion = -1
    private var lastHistoryPushTime = Date()

    // Only ever push RECENT history over the socket, never the whole thing: the full
    // history can be many MB and would blow past the client's WebSocket message-size
    // limit (tearing the connection down). Clients load the full history once via
    // GET /history and merge these deltas on top. A small overlap covers races.
    private let recentHistoryWindow: TimeInterval = 3600   // seed with the last hour
    private let historyOverlap: TimeInterval = 5

    init(ws: WebSocket) { self.ws = ws }

    func start() {
        // Push the current queue + recent history right away so a freshly-connected
        // client is in sync immediately (not only once something next changes).
        send(.queue(listQueue()))
        lastQueueSignature = queueSignature()
        send(.history(history.since(time: Date().addingTimeInterval(-recentHistoryWindow))))
        lastHistoryVersion = history.version
        lastHistoryPushTime = Date()

        task = ws.eventLoop.scheduleRepeatedTask(initialDelay: .zero, delay: .milliseconds(50)) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        let playing = !audioPlayer.isPaused && audioPlayer.playingTrack != nil
        tickCount &+= 1

        // levels: high-rate while playing; one final silent frame on stop
        if audioPlayer.outputLevels.available {
            if playing {
                sentSilentLevels = false
                send(.levels(audioPlayer.outputLevels))
            } else if !sentSilentLevels {
                sentSilentLevels = true
                send(.levels(.silent))
            }
        }

        // queue: check ~5×/s, push only when it actually changed
        if tickCount % 5 == 0 {
            let signature = queueSignature()
            if signature != lastQueueSignature {
                lastQueueSignature = signature
                send(.queue(listQueue()))
            }
        }

        // position: ~2×/s while playing, to keep the progress bar moving
        if playing, tickCount % 10 == 0 {
            send(.position(PlaybackPosition(position: audioPlayer.playingTrackPosition,
                                            duration: audioPlayer.playingTrackDuration)))
        }

        // history: check ~5×/s, push just the new events (since the last push, with
        // a small overlap) when a play/skip landed — the client merges them
        if tickCount % 5 == 0 {
            let version = history.version
            if version != lastHistoryVersion {
                lastHistoryVersion = version
                send(.history(history.since(time: lastHistoryPushTime.addingTimeInterval(-historyOverlap))))
                lastHistoryPushTime = Date()
            }
        }
    }

    // Captures what a client cares about for the queue: pause state, the current
    // track, and the pending order. Position is deliberately excluded (that's the
    // position frames' job) so it doesn't force a full queue resend every tick.
    private func queueSignature() -> String {
        let current = audioPlayer.playingTrack?.SHA1 ?? "-"
        return "\(audioPlayer.isPaused)|\(current)|\(audioPlayer.trackQueue.joined(separator: ","))"
    }

    private func send(_ frame: StreamFrame) {
        guard let data = try? encoder.encode(frame),
              let json = String(data: data, encoding: .utf8) else { return }
        ws.send(json)
    }
}
