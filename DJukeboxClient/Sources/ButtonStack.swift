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

