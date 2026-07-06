import Foundation
import os

// A thread-safe sink for the per-channel output loudness measured on the realtime
// audio thread by the playback gain tap (see AudioGainTap.gainTapProcess), drained
// on the main thread by AudioLevelMonitor to drive the vacuum-tube VU meter.
//
// Writes keep the PEAK seen since the last drain ("peak hold"), so the display
// sampler can run slower than the audio callback (buffers arrive ~40×/s; the
// monitor samples ~30×/s) without dropping transients. Drain returns that peak
// and resets to zero, so no energy is counted twice.
//
// @unchecked Sendable: all mutable state lives behind the unfair lock, matching
// the PlaybackGain pattern in AudioGainTap.swift. Written on the audio thread,
// read on the main thread.
public final class AudioLevelMeter: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (left: Float(0), right: Float(0)))

    public init() {}

    // Called from the realtime audio thread, once per processed buffer.
    func record(left: Float, right: Float) {
        state.withLock {
            if left  > $0.left  { $0.left  = left  }
            if right > $0.right { $0.right = right }
        }
    }

    // Called from the main thread at display rate: returns the peak since the last
    // drain and resets, so successive drains don't double-count the same samples.
    func drain() -> (left: Float, right: Float) {
        state.withLock {
            let v = $0
            $0 = (0, 0)
            return v
        }
    }

    // Discard any held level (e.g. when the queue is cleared).
    func reset() { state.withLock { $0 = (0, 0) } }
}
