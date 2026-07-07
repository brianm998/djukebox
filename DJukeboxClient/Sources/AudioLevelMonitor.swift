import Foundation
import os
import DJukeboxCommon

// Drives the vacuum-tube VU meter. A display-rate timer on the main run loop
// samples the current per-channel loudness — from the local playback tap
// (AudioLevelMeter) when THIS device is decoding the audio, or from levels pushed
// over the server's /stream socket (fed in via ingestRemoteLevels) when the server
// is the one playing (remote queue) — trailing-averages it over ~0.5 s to kill
// flicker, maps it onto a perceptual 0...1 scale, and publishes values the tube
// view animates.
//
// @MainActor: the timer fires on the main run loop and every @Published mutation
// happens there; it also reads TrackFetcher's @MainActor state directly (F30).
// The only cross-thread state (the pushed remote levels) lives behind a lock, so
// ingestRemoteLevels can still be called from the stream socket's receive side.
@MainActor
public final class AudioLevelMonitor: ObservableObject {
    // Smoothed, normalized per-channel levels in 0...1 for the view (0 = tube at
    // rest / grey, 1 = fully lit golden-orange).
    @Published public private(set) var left: Double = 0
    @Published public private(set) var right: Double = 0

    private let localMeter: AudioLevelMeter
    private weak var trackFetcher: TrackFetcher?

    // Latest levels pushed from the server (remote mode). Written from the stream
    // socket's receive thread (via ingestRemoteLevels), read on the main thread.
    private let remoteLevels = OSAllocatedUnfairLock(initialState: AudioLevels.unavailable)

    // display sampling + trailing-average window (~0.5 s of samples)
    private let sampleHz = 30.0
    private let windowSize = 15                     // 0.5 s * 30 Hz
    private var leftRing: [Double]
    private var rightRing: [Double]
    private var ringIndex = 0

    // nonisolated(unsafe): Timer isn't Sendable, so a plain @MainActor-isolated
    // stored property can't be touched from deinit (always nonisolated). Only
    // ever written from start()/stop() (both @MainActor) and read here in deinit
    // for a one-time invalidate() — Timer.invalidate() is documented safe to call
    // from any thread, so this is a narrow, safe escape hatch (same spirit as
    // ServerStreamSocket's nonisolated deinit teardown).
    private nonisolated(unsafe) var timer: Timer?

    public init(localMeter: AudioLevelMeter, trackFetcher: TrackFetcher?) {
        self.localMeter = localMeter
        self.trackFetcher = trackFetcher
        self.leftRing = Array(repeating: 0, count: windowSize)
        self.rightRing = Array(repeating: 0, count: windowSize)
        start()
    }

    deinit { timer?.invalidate() }

    // Called from the stream socket (any thread) with the latest pushed levels.
    public func ingestRemoteLevels(_ levels: AudioLevels) {
        remoteLevels.withLock { $0 = levels }
    }

    public func start() {
        timer?.invalidate()
        // Scheduled on the main run loop; the block runs on the main thread in
        // practice (so this hop is an immediate same-thread resumption, not a real
        // dispatch), but Timer's closure is nonisolated/@Sendable, and tick() is
        // @MainActor now (F30, since it reads TrackFetcher directly) — so hop
        // explicitly rather than rely on the (untracked) thread the timer fires on.
        let t = Timer(timeInterval: 1.0 / sampleHz, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let isRemote = (trackFetcher?.queueType == .remote)
        let paused = trackFetcher?.audioPlayer.isPaused ?? true

        var rawLeft = 0.0
        var rawRight = 0.0

        if paused {
            // feed silence so the average decays smoothly to rest
        } else if isRemote {
            let remote = remoteLevels.withLock { $0 }
            if remote.available {
                rawLeft = Double(remote.left)
                rawRight = Double(remote.right)
            }
        } else {
            let (l, r) = localMeter.drain()
            rawLeft = Double(l)
            rawRight = Double(r)
        }

        // trailing average over the last ~0.5 s
        leftRing[ringIndex] = rawLeft
        rightRing[ringIndex] = rawRight
        ringIndex = (ringIndex + 1) % windowSize
        let avgLeft = leftRing.reduce(0, +) / Double(windowSize)
        let avgRight = rightRing.reduce(0, +) / Double(windowSize)

        let newLeft = normalize(avgLeft)
        let newRight = normalize(avgRight)

        // don't republish (and re-render SwiftUI) when idle and unchanged
        let eps = 0.004
        if abs(newLeft - left) > eps || abs(newRight - right) > eps {
            left = newLeft
            right = newRight
        }
    }

    // Map a linear amplitude onto a perceptual 0...1 via a dB window, so quiet
    // passages stay dim and loud ones drive the filament bright, with a usable
    // spread in between. Silence clamps to 0 (tube at rest).
    private func normalize(_ linear: Double) -> Double {
        guard linear > 0.00003 else { return 0 }
        let db = 20 * log10(linear)          // <= 0 dBFS
        let floorDB = -45.0
        let n = (db - floorDB) / (0 - floorDB)
        return min(1, max(0, n))
    }
}
