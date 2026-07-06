import Foundation
import DJukeboxCommon

// Drives the vacuum-tube VU meter. A display-rate timer on the main run loop
// samples the current per-channel loudness — from the local playback tap
// (AudioLevelMeter) when THIS device is decoding the audio, or by polling the
// server's /levels endpoint when the server is the one playing (remote queue) —
// trailing-averages it over ~0.5 s to kill flicker, maps it onto a perceptual
// 0...1 scale, and publishes values the tube view animates.
//
// @unchecked Sendable / not @MainActor, matching the client's playback core
// (TrackFetcher et al.): the timer fires on the main run loop and every @Published
// mutation happens there, and the one field the audio thread touches lives behind
// AudioLevelMeter's lock. See the client concurrency note in AsyncAudioPlayer.
public final class AudioLevelMonitor: ObservableObject, @unchecked Sendable {
    // Smoothed, normalized per-channel levels in 0...1 for the view (0 = tube at
    // rest / grey, 1 = fully lit golden-orange).
    @Published public private(set) var left: Double = 0
    @Published public private(set) var right: Double = 0

    private let localMeter: AudioLevelMeter
    private let server: ServerType
    private weak var trackFetcher: TrackFetcher?

    // display sampling + trailing-average window (~0.5 s of samples)
    private let sampleHz = 30.0
    private let windowSize = 15                     // 0.5 s * 30 Hz
    private var leftRing: [Double]
    private var rightRing: [Double]
    private var ringIndex = 0

    // latest raw levels from the server poll (remote queue)
    private var remoteLeft: Float = 0
    private var remoteRight: Float = 0
    private var remoteAvailable = false
    private var remotePollInFlight = false
    private var ticksSincePoll = 0

    private var timer: Timer?

    public init(localMeter: AudioLevelMeter, server: ServerType, trackFetcher: TrackFetcher?) {
        self.localMeter = localMeter
        self.server = server
        self.trackFetcher = trackFetcher
        self.leftRing = Array(repeating: 0, count: windowSize)
        self.rightRing = Array(repeating: 0, count: windowSize)
        start()
    }

    deinit { timer?.invalidate() }

    public func start() {
        timer?.invalidate()
        // Scheduled on the main run loop; the block only touches main-thread state
        // (and the lock-guarded meter), so no cross-actor hop is needed — this
        // mirrors Client's 1 s refresh timer.
        let t = Timer(timeInterval: 1.0 / sampleHz, repeats: true) { [weak self] _ in
            self?.tick()
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
            pollServerIfDue()
            if remoteAvailable {
                rawLeft = Double(remoteLeft)
                rawRight = Double(remoteRight)
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

    // Poll /levels a few times a second (not every display tick) while the server
    // is playing; guard against overlapping requests.
    private func pollServerIfDue() {
        ticksSincePoll += 1
        guard !remotePollInFlight, ticksSincePoll >= 3 else { return }   // ~10 Hz
        ticksSincePoll = 0
        remotePollInFlight = true
        // Strong self, set directly on the main queue — mirrors TrackFetcher's
        // server-callback pattern. The closure is held only by the transient
        // URLSession task, so it can't form a retain cycle.
        server.currentLevels { levels, _ in
            DispatchQueue.main.async {
                self.remotePollInFlight = false
                if let levels = levels {
                    self.remoteAvailable = levels.available
                    self.remoteLeft = levels.left
                    self.remoteRight = levels.right
                } else {
                    self.remoteAvailable = false
                }
            }
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
