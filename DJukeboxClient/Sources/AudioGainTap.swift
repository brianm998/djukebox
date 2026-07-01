import Foundation
import AVFoundation
import MediaToolbox
import os
import DJukeboxCommon

// AVPlayer.volume is capped at 1.0, so it can only attenuate. To BOOST local
// (streaming) playback above unity — matching what the server does with
// AVAudioUnitEQ — we tap the decoded PCM with an MTAudioProcessingTap and
// multiply every sample by a gain factor > 1.0. The tap sits on the AVPlayer's
// decoded output, so streaming/buffering is untouched.
//
// Each AVPlayerItem gets its OWN PlaybackGain (and its own tap), so a track's
// gain can never bleed into the next one during the queue transition. The state
// is read on the realtime audio thread and written from the main / networking
// threads, so it is guarded by an OSAllocatedUnfairLock (iOS 16+/macOS 13+). The
// critical section is a two-field copy — negligible cost on the audio thread, and
// contention is effectively nil (writes are rare: per-track and slider drags).
// @unchecked Sendable: all mutable state lives behind the lock.
public final class PlaybackGain: @unchecked Sendable {
    private struct State {
        var linearGain: Float = 1.0   // 1.0 = unity, 2.0 = +6 dB, etc.
        var isFloat: Bool = true      // is the tap's negotiated format 32-bit float?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    // Same clamp/units as the server: decibels in, linear multiplier stored.
    public func setDecibels(_ db: Double) {
        let clamped = max(-24.0, min(24.0, db))
        let linear = Float(pow(10.0, clamped / 20.0))
        state.withLock { $0.linearGain = linear }
    }

    fileprivate func setIsFloat(_ value: Bool) {
        state.withLock { $0.isFloat = value }
    }

    // one locked read for the audio callback
    fileprivate var snapshot: (gain: Float, isFloat: Bool) {
        state.withLock { ($0.linearGain, $0.isFloat) }
    }

    // Builds an audio mix carrying a fresh tap bound to this gain, for one asset's
    // audio track. Attach it to an AVPlayerItem via `item.audioMix`.
    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix {
        // +1 retain handed to the tap via clientInfo; released in gainTapFinalize
        let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: gainTapInit,
            finalize: gainTapFinalize,
            prepare: gainTapPrepare,
            unprepare: gainTapUnprepare,
            process: gainTapProcess)

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PreEffects, &tap)

        let params = AVMutableAudioMixInputParameters(track: track)
        if status == noErr, let tap = tap {
            params.audioTapProcessor = tap
        } else {
            // creation failed → gainTapFinalize won't run, so balance the retain
            Unmanaged<PlaybackGain>.fromOpaque(clientInfo).release()
            Log.e("could not create audio gain tap: \(status)")
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}

// Escape hatch for handing a non-Sendable AVFoundation object (AVPlayerItem /
// AVAudioMix) across a Sendable callback boundary. Safe here because the boxed
// value is only ever touched on the main thread.
final class UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - MTAudioProcessingTap C callbacks (non-capturing; state via tap storage)

private let gainTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    // stash the (already-retained) PlaybackGain pointer for the other callbacks
    tapStorageOut.pointee = clientInfo
}

private let gainTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    // balance the passRetained() done when the tap was created
    Unmanaged<PlaybackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let gainTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let gain = Unmanaged<PlaybackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let asbd = processingFormat.pointee
    gain.setIsFloat((asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.mBitsPerChannel == 32)
}

private let gainTapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let gainTapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in

    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut,
                                                    flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }

    let (gain, isFloat) = Unmanaged<PlaybackGain>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().snapshot
    // passthrough when there's nothing to do or the format isn't 32-bit float
    guard isFloat, gain != 1.0 else { return }

    let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    for buffer in buffers {
        guard let raw = buffer.mData else { continue }
        let samples = raw.assumingMemoryBound(to: Float.self)
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
        for i in 0 ..< count {
            samples[i] *= gain
        }
    }
}
