#if os(iOS)
import AVFoundation
import Foundation
import MediaPlayer
import DJukeboxCommon

// Connects playback to the iOS system: the lock screen / Control Center "Now
// Playing" info, the remote (lock screen, headphone button, car) commands, and
// the audio-session interruption and route-change notifications.
//
// TrackFetcher calls refresh() whenever what it displays changes; commands act
// on whichever queue (local or remote) is active. Interruptions and route
// changes only concern the LOCAL queue: with the remote queue the server makes
// the sound, not the phone.
//
// This deliberately never calls AVAudioSession.setActive: doing so from the
// playback path broke offline playback before. AppDelegate sets the category.
@MainActor
public final class NowPlayingCoordinator {

    private enum Command: Sendable {
        case play, pause, togglePlayPause, nextTrack
    }

    // The command center and info center are process-wide, but a new Client (and
    // so a new coordinator) is built on every scan/reconnect: the newest one
    // owns them.
    private static weak var current: NowPlayingCoordinator?

    // weak: TrackFetcher only points back weakly too, Client owns this object
    weak var trackFetcher: TrackFetcher?

    // set when an interruption paused local playback, so only that gets resumed
    private var wasPlayingBeforeInterruption = false

    private var interruptionTask: Task<Void, Never>?
    private var routeChangeTask: Task<Void, Never>?

    init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
        Self.current = self
        registerRemoteCommands()
        observeInterruptions()
        observeRouteChanges()
        refresh()
    }

    deinit {
        interruptionTask?.cancel()
        routeChangeTask?.cancel()
    }

    // MARK: - Now Playing info

    func refresh() {
        // something else resumed local playback, so there is nothing left for the
        // end of the interruption to do (and a later user pause must stick)
        if wasPlayingBeforeInterruption,
           trackFetcher?.queues[.local]?.isPaused == false
        {
            wasPlayingBeforeInterruption = false
        }

        guard Self.current === self else { return }

        let center = MPNowPlayingInfoCenter.default()
        let nextTrackCommand = MPRemoteCommandCenter.shared().nextTrackCommand

        guard let trackFetcher, let track = trackFetcher.currentTrack else {
            nextTrackCommand.isEnabled = false
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        nextTrackCommand.isEnabled = true

        let paused = isActiveQueuePaused

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.Title,
            MPMediaItemPropertyArtist: track.Artist,
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = track.Album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = track.timeInterval ?? trackFetcher.playingQueue?.playingTrackDuration,
           duration.isFinite
        {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        // never hand the system a non-finite elapsed time
        let position = trackFetcher.progressBarLevel?.level
          ?? trackFetcher.audioPlayer.player?.playingTrackPosition
          ?? 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.isFinite ? position : 0

        center.nowPlayingInfo = info
        center.playbackState = paused ? .paused : .playing
    }

    private var isActiveQueuePaused: Bool {
        guard let trackFetcher else { return true }
        switch trackFetcher.queueType {
        case .local:
            return trackFetcher.queues[.local]?.isPaused ?? true
        case .remote:
            // ServerAudioPlayer.isPaused is a cache the server pushes never
            // update; the playing queue carries the real state
            return trackFetcher.playingQueue?.isPaused ?? true
        case nil:
            return true
        }
    }

    // MARK: - remote commands

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand, as: .play)
        register(center.pauseCommand, as: .pause)
        register(center.togglePlayPauseCommand, as: .togglePlayPause)
        register(center.nextTrackCommand, as: .nextTrack)
        center.previousTrackCommand.isEnabled = false
    }

    private func register(_ remoteCommand: MPRemoteCommand, as command: Command) {
        remoteCommand.removeTarget(nil) // drop any previous coordinator's handler
        remoteCommand.isEnabled = true
        // @Sendable: MediaPlayer does not promise to call this on the main actor
        remoteCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.perform(command)
            }
            return .success
        }
    }

    private func perform(_ command: Command) async {
        guard let trackFetcher,
              let player = trackFetcher.audioPlayer.player
        else { return }

        do {
            switch command {
            case .play:
                wasPlayingBeforeInterruption = false
                _ = try await player.resumePlaying()
            case .pause:
                wasPlayingBeforeInterruption = false
                // guarded: pausing the local player twice would resume it
                if !isActiveQueuePaused {
                    _ = try await player.pausePlaying()
                }
            case .togglePlayPause:
                await perform(isActiveQueuePaused ? .play : .pause)
                return
            case .nextTrack:
                guard let track = trackFetcher.currentTrack else { return }
                // index -1 means "the playing track", which skips it on both queues
                _ = try await player.stopPlayingTrack(withHash: track.SHA1, atIndex: -1)
            }
        } catch {
            Log.e("could not handle remote command \(command): \(error)")
        }
        trackFetcher.refreshQueue()
    }

    // MARK: - interruptions and route changes

    private func observeInterruptions() {
        let events = NotificationCenter.default
          .notifications(named: AVAudioSession.interruptionNotification)
          .compactMap { note -> (type: UInt, options: UInt)? in
              guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
              else { return nil }
              let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
              return (type, options ?? 0)
          }
        interruptionTask = Task { [weak self] in
            for await event in events {
                switch AVAudioSession.InterruptionType(rawValue: event.type) {
                case .began:
                    await self?.interruptionBegan()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: event.options)
                    await self?.interruptionEnded(shouldResume: options.contains(.shouldResume))
                default:
                    break
                }
            }
        }
    }

    private func observeRouteChanges() {
        let reasons = NotificationCenter.default
          .notifications(named: AVAudioSession.routeChangeNotification)
          .compactMap { note -> UInt? in
              note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
          }
        routeChangeTask = Task { [weak self] in
            for await reason in reasons {
                // e.g. headphones unplugged: don't carry on out of the speaker
                if AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable {
                    await self?.outputDeviceRemoved()
                }
            }
        }
    }

    private func interruptionBegan() async {
        if await pauseLocalIfPlaying() {
            wasPlayingBeforeInterruption = true
        }
    }

    private func interruptionEnded(shouldResume: Bool) async {
        let resume = shouldResume && wasPlayingBeforeInterruption
        wasPlayingBeforeInterruption = false
        guard resume, let local = trackFetcher?.queues[.local] else { return }
        do {
            _ = try await local.resumePlaying()
        } catch {
            Log.e("could not resume after interruption: \(error)")
        }
        trackFetcher?.refreshQueue()
    }

    private func outputDeviceRemoved() async {
        // an interruption ending after this must not start the speaker either
        wasPlayingBeforeInterruption = false
        _ = await pauseLocalIfPlaying()
    }

    // returns true if the local queue was playing and has now been paused
    private func pauseLocalIfPlaying() async -> Bool {
        guard let local = trackFetcher?.queues[.local] as? AsyncAudioPlayer,
              local.player.playingTrack != nil,
              !local.isPaused // pausing a paused local player would resume it
        else { return false }
        do {
            _ = try await local.pausePlaying()
        } catch {
            Log.e("could not pause local playback: \(error)")
            return false
        }
        trackFetcher?.refreshQueue()
        return true
    }
}
#endif
