import SwiftUI
import DJukeboxCommon

fileprivate let ios_button_size: CGFloat = 60

public struct PlayButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    public init(audioPlayer: ViewObservableAudioPlayer) {
        self.audioPlayer = audioPlayer
    }
    
    public var body: some View {
        Button(action: {
            self.audioPlayer.player?.resumePlaying() { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("play: \(audioTrack)")
                }
            }
        }) {
            #if os(iOS)
            Image(systemName: "play.fill")
              .resizable()
              .frame(width: ios_button_size, height: ios_button_size)
            #else
            Text("\u{25B6}").font(.largeTitle)
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

public struct PauseButton: View {
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer
    
    public init(audioPlayer: ViewObservableAudioPlayer) {
        self.audioPlayer = audioPlayer
    }
    
    public var body: some View {
        Button(action: {
            self.audioPlayer.player?.pausePlaying() { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("pause: \(audioTrack)")
                }
            }
        }) {
            #if os(iOS)
            Image(systemName: "pause.fill")
              .resizable()
              .frame(width: ios_button_size, height: ios_button_size)
            #else
            Text("\u{23F8}").font(.largeTitle)
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

public struct SkipCurrentTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: {
                self.trackFetcher.audioPlayer.player?.stopPlayingTrack(withHash: self.trackFetcher.currentTrack?.SHA1 ?? "",
                                                         atIndex: -1) { audioTrack, error in
                if let error = error {
                    Log.e("DOH")
                } else {
                    Log.d("skip: \(audioTrack)")
                }
                self.trackFetcher.refreshQueue()
            }
        }) {
            #if os(iOS)
            Image(systemName: "stop.fill")
              .resizable()
              .frame(width: ios_button_size, height: ios_button_size)
            #else
            Text("\u{23F9}").font(.largeTitle) // stop
            #endif
        }.buttonStyle(PlainButtonStyle())
    }
}

public struct PlayRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: {
            self.trackFetcher.playRandomTrack()
        }) {
            Text("Random")
        }
    }
}

public struct PlayNewRandomTrackButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: {
            self.trackFetcher.playNewRandomTrack()
        }) {
            Text("New Random")
        }
    }
}

public struct ShuffleQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: {
            self.trackFetcher.shuffleQueue()
        }) {
            Text("Shuffle Q")
        }
    }
}

public struct ClearQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: { self.trackFetcher.clearPlayingQueue() }) {
            Text("Clear Q")
              .foregroundColor(Color.red)
        }
    }
}

public struct RefreshTracksFromServerButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        Button(action: { self.trackFetcher.refreshTracks() }) {
            Text("Refresh")
        }
    }
}

public struct RefreshQueueButton: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        Button(action: { self.trackFetcher.refreshQueue() }) {
            Text("Refresh Q")
        }
    }
}

public struct PlayUntilButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var showingPicker = false
    @State private var selectedTime = Date()

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        Button("Play Until") {
            selectedTime = Date().addingTimeInterval(3600)
            showingPicker = true
        }
        .sheet(isPresented: $showingPicker) {
            VStack(spacing: 24) {
                Text("Play Until").font(.headline)
                #if os(iOS)
                DatePicker("", selection: $selectedTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                #else
                DatePicker("", selection: $selectedTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .frame(maxWidth: 360)
                #endif
                HStack {
                    Button("Cancel") { showingPicker = false }
                    Spacer()
                    Button("Confirm") {
                        trackFetcher.playUntil(date: selectedTime)
                        showingPicker = false
                    }
                    .bold()
                }
            }
            .padding()
        }
    }
}

public struct PlayForButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var showingPicker = false
    @State private var hours = 1
    @State private var minutes = 0

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        Button("Play For") {
            hours = 1
            minutes = 0
            showingPicker = true
        }
        .sheet(isPresented: $showingPicker) {
            VStack(spacing: 24) {
                Text("Play For").font(.headline)
                #if os(iOS)
                HStack(spacing: 0) {
                    Picker("Hours", selection: $hours) {
                        ForEach(0...23, id: \.self) { h in Text("\(h)h").tag(h) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0...59, id: \.self) { m in Text("\(m)m").tag(m) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                }
                #else
                HStack(spacing: 16) {
                    Stepper("\(hours)h", value: $hours, in: 0...23)
                    Stepper("\(minutes)m", value: $minutes, in: 0...59)
                }
                .frame(minWidth: 240)
                #endif
                HStack {
                    Button("Cancel") { showingPicker = false }
                    Spacer()
                    Button("Confirm") {
                        let duration = TimeInterval(hours * 3600 + minutes * 60)
                        trackFetcher.playUntil(date: Date().addingTimeInterval(duration))
                        showingPicker = false
                    }
                    .bold()
                }
            }
            .padding()
        }
    }
}

// The volume-boost sheet content, shared by the Mac/iPad button and the iPhone
// action-sheet entry. Dragging the slider auditions the gain LIVE on the
// currently-playing track (server-side); picking a scope persists it. The slider
// pre-fills with the track's saved gain, and Cancel reverts the live audition.
public struct TrackVolumeSheet: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @Binding var isPresented: Bool
    @State private var decibels: Double = 0
    @State private var originalDecibels: Double = 0
    @State private var userInteracting = false
    @State private var appliedSavedGain = false
    @State private var committed = false
    // user-adjustable slider range (dB), defaulting to a -8 … +12 span. The +/-
    // buttons above each end widen or narrow it, kept within the ±24 dB the audio
    // pipeline allows.
    @State private var lowerBound: Double = -8
    @State private var upperBound: Double = 12
    private let rangeStep: Double = 1     // dB each +/- tap moves an end
    private let minSpan: Double = 4       // smallest span so the ends can't cross
    private let boundLimit: Double = 24   // audio pipeline clamps gain to ±24 dB

    public init(trackFetcher: TrackFetcher, isPresented: Binding<Bool>) {
        self.trackFetcher = trackFetcher
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 20) {
            if let track = trackFetcher.currentTrack {
                Text("Boost Volume").font(.headline)
                Text(track.Title).font(.subheadline).foregroundColor(.gray)

                VStack(spacing: 6) {
                    // a -/+ pair above each end to narrow or widen that end of the range
                    HStack {
                        rangeAdjuster(minus: { adjustLower(by: -rangeStep) },
                                      plus:  { adjustLower(by:  rangeStep) })
                        Spacer()
                        rangeAdjuster(minus: { adjustUpper(by: -rangeStep) },
                                      plus:  { adjustUpper(by:  rangeStep) })
                    }
                    HStack {
                        Image(systemName: "speaker.fill")
                        // reduction as well as boost, over the user-adjustable range
                        Slider(value: $decibels, in: lowerBound...upperBound, step: 0.5,
                               onEditingChanged: { editing in userInteracting = editing })
                          .frame(minWidth: 200)
                        Image(systemName: "speaker.wave.3.fill")
                        // total range at the end of the bar, updating as the ends move
                        Text(String(format: "%+g…%+g dB", lowerBound, upperBound))
                          .font(.caption).monospacedDigit().foregroundColor(.gray)
                    }
                }
                Text(String(format: "%+.1f dB", decibels)).monospacedDigit()

                Text("Apply to:").font(.subheadline)
                VStack(alignment: .leading, spacing: 8) {
                    scopeRow("This Track:", track.Title, .track, track)
                    if let album = track.Album {
                        scopeRow("This Album:", album, .album, track)
                    }
                    scopeRow("This Artist:", track.Band, .artist, track)
                }

                Button("Cancel") { isPresented = false }
            } else {
                Text("Nothing playing")
                Button("Cancel") { isPresented = false }
            }
        }
        .padding()
        .frame(minWidth: 300)
        .onChange(of: decibels) { newValue in
            // live-audition on every step so the user hears the change while
            // dragging — but only for real drags, not the programmatic prefill
            // (which would otherwise briefly reset an already-boosted track)
            if userInteracting { trackFetcher.previewVolume(decibels: newValue) }
        }
        .onChange(of: trackFetcher.currentTrackGainDB) { saved in
            // apply the freshly-fetched saved gain once, but never clobber a drag
            // in progress (onEditingChanged tracks real user interaction)
            if !appliedSavedGain, !userInteracting {
                appliedSavedGain = true
                ensureBoundsContain(saved)
                decibels = saved
                originalDecibels = saved
            }
        }
        .onAppear {
            appliedSavedGain = false
            userInteracting = false
            committed = false
            // best-effort immediate prefill from the last-known value…
            let cached = trackFetcher.currentTrackGainDB
            ensureBoundsContain(cached)
            decibels = cached
            originalDecibels = cached
            // …then fetch THIS track's saved gain by its sha1 (onChange applies it)
            if let sha1 = trackFetcher.currentTrack?.SHA1 {
                trackFetcher.refreshSavedGain(forHash: sha1)
            }
        }
        .onDisappear {
            // if the user auditioned a level but didn't save it (Cancel, or swipe
            // to dismiss), restore the level that was in effect when we opened
            if !committed {
                trackFetcher.previewVolume(decibels: originalDecibels)
            }
        }
    }

    // One "This X:  <name>" row that applies the current slider value to that scope.
    private func scopeRow(_ label: String, _ name: String,
                          _ scope: VolumeScope, _ track: AudioTrack) -> some View {
        Button { apply(scope, track) } label: {
            HStack(spacing: 8) {
                Text(label).frame(width: 84, alignment: .trailing)
                Text(name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
    }

    private func apply(_ scope: VolumeScope, _ track: AudioTrack) {
        committed = true
        trackFetcher.setVolume(decibels: decibels, scope: scope, for: track)
        isPresented = false
    }

    // A "-  +" pair that steps one end of the slider's range.
    private func rangeAdjuster(minus: @escaping () -> Void,
                               plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: minus) { Image(systemName: "minus.circle") }
            Button(action: plus)  { Image(systemName: "plus.circle") }
        }
        .buttonStyle(.plain)
    }

    // Move the reduction (low) end, kept within -24…0 and a minSpan gap below the top.
    private func adjustLower(by delta: Double) {
        let v = max(-boundLimit, min(0, lowerBound + delta))
        lowerBound = min(v, upperBound - minSpan)
        decibels = max(lowerBound, min(upperBound, decibels))
    }

    // Move the boost (high) end, kept within 0…+24 and a minSpan gap above the bottom.
    private func adjustUpper(by delta: Double) {
        let v = max(0, min(boundLimit, upperBound + delta))
        upperBound = max(v, lowerBound + minSpan)
        decibels = max(lowerBound, min(upperBound, decibels))
    }

    // Widen the range so a saved/prefilled gain sits inside it (else the slider
    // thumb would pin to an end and misrepresent the stored value). Whichever end
    // the value is past is moved out to the value exactly.
    private func ensureBoundsContain(_ value: Double) {
        if value < lowerBound { lowerBound = max(-boundLimit, value) }
        if value > upperBound { upperBound = min(boundLimit, value) }
    }
}

// A short signed dB label for a gain (e.g. "+6 dB", "-2 dB"), or nil at 0 dB.
public func volumeGainLabel(_ decibels: Double) -> String? {
    guard decibels != 0 else { return nil }
    return String(format: "%+g dB", decibels)
}

// A short label for the master attenuation: "Full" at (or effectively at) 0 dB,
// else a whole-dB cut like "-12 dB" (rounded so it never shows "-0 dB").
public func masterVolumeLabel(_ decibels: Double) -> String {
    let rounded = decibels.rounded()
    return rounded >= 0 ? "Full" : String(format: "%.0f dB", rounded)
}

// The top-level master volume control: one global attenuation that only cuts from
// full volume (0 dB) down to a floor, applied on top of every per-track/album/
// artist gain. Dragging auditions live; releasing persists it to the server.
// Shared by the Mac/iPad button rows and the iPhone controls.
public struct MasterVolumeControl: View {
    @ObservedObject var trackFetcher: TrackFetcher
    private let floor: Double = -30   // reduction-only: -30 dB … 0 dB (full, right end)

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text("Master").font(.caption)
            Image(systemName: "speaker.fill")
            // full volume sits at the right end (0 dB); dragging left attenuates.
            // The binding auditions on every step; onEditingChanged persists on release.
            Slider(value: Binding(get: { trackFetcher.masterGainDB },
                                  set: { trackFetcher.previewMasterGain(decibels: $0) }),
                   in: floor...0, step: 0.5,
                   onEditingChanged: { editing in
                       if !editing { trackFetcher.commitMasterGain() }
                   })
              .frame(minWidth: 120)
            Image(systemName: "speaker.wave.3.fill")
            Text(masterVolumeLabel(trackFetcher.masterGainDB))
              .font(.caption).monospacedDigit()
              .frame(width: 52, alignment: .leading)
        }
        .onAppear { trackFetcher.refreshMasterGain() }
    }
}

// Boosts the volume of the currently-playing track (Mac / iPad). Opens the shared
// TrackVolumeSheet. On iPhone the same sheet is reached from the "Actions" menu.
public struct TrackVolumeButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var showingPicker = false

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        Button(action: { showingPicker = true }) {
            if let label = volumeGainLabel(trackFetcher.currentTrackGainDB) {
                Text("Volume  \(label)")
            } else {
                Text("Volume")
            }
        }
        .disabled(trackFetcher.currentTrack == nil)
        .sheet(isPresented: $showingPicker) {
            TrackVolumeSheet(trackFetcher: trackFetcher, isPresented: $showingPicker)
        }
    }
}

