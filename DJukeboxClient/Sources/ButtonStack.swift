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

    public init(trackFetcher: TrackFetcher, isPresented: Binding<Bool>) {
        self.trackFetcher = trackFetcher
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 20) {
            if let track = trackFetcher.currentTrack {
                Text("Boost Volume").font(.headline)
                Text(track.Title).font(.subheadline).foregroundColor(.gray)

                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $decibels, in: 0...12, step: 0.5,
                           onEditingChanged: { editing in userInteracting = editing })
                      .frame(minWidth: 200)
                    Image(systemName: "speaker.wave.3.fill")
                }
                Text(String(format: "+%.1f dB", decibels)).monospacedDigit()

                Text("Apply this boost to:").font(.subheadline)
                HStack(spacing: 12) {
                    Button("This Track") { apply(.track, track) }
                    if track.Album != nil {
                        Button("This Album") { apply(.album, track) }
                    }
                    Button("This Artist") { apply(.artist, track) }
                }

                Button("Cancel") {
                    // undo the live audition (restore what was saved when we opened)
                    trackFetcher.previewVolume(decibels: originalDecibels)
                    isPresented = false
                }
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
                decibels = saved
                originalDecibels = saved
            }
        }
        .onAppear {
            appliedSavedGain = false
            userInteracting = false
            // best-effort immediate prefill from the last-known value…
            let cached = trackFetcher.currentTrackGainDB
            decibels = cached
            originalDecibels = cached
            // …then fetch THIS track's saved gain by its sha1 (onChange applies it)
            if let sha1 = trackFetcher.currentTrack?.SHA1 {
                trackFetcher.refreshSavedGain(forHash: sha1)
            }
        }
    }

    private func apply(_ scope: VolumeScope, _ track: AudioTrack) {
        trackFetcher.setVolume(decibels: decibels, scope: scope, for: track)
        isPresented = false
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
        Button("Volume") { showingPicker = true }
        .disabled(trackFetcher.currentTrack == nil)
        .sheet(isPresented: $showingPicker) {
            TrackVolumeSheet(trackFetcher: trackFetcher, isPresented: $showingPicker)
        }
    }
}

