import SwiftUI
import DJukeboxCommon
import DJukeboxClient

// Replaces the old "Offline" toggle. In offline mode (no server) it offers to
// "Scan" for one; while connected it shows "Local", which drops back to offline.
public struct OfflineScanButton: View {
    @ObservedObject var trackFetcher: TrackFetcher
    let onScan: () -> Void
    let onGoOffline: () -> Void

    public init(trackFetcher: TrackFetcher,
                onScan: @escaping () -> Void,
                onGoOffline: @escaping () -> Void)
    {
        self.trackFetcher = trackFetcher
        self.onScan = onScan
        self.onGoOffline = onGoOffline
    }

    public var body: some View {
        if trackFetcher.useLocalContentOnly {
            Button(action: onScan) {
                Text("Scan").underline().foregroundColor(Color.blue)
            }
        } else {
            Button(action: {
                // remember the play-local choice first so a later scan can restore it
                self.onGoOffline()
                // offline mode always plays local, so force the queue too
                try? self.trackFetcher.watch(queue: .local)
                self.trackFetcher.useLocalContentOnly = true
            }) {
                Text("Local").underline().foregroundColor(Color.blue)
            }
        }
    }
}

public struct VerticalPlayingTimeRemainingView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        return VStack {
            Text(format(duration: trackFetcher.totalDuration))
            Text(string(forTime: trackFetcher.completionTime))
        }
    }
}

public struct HorizontalPlayingTimeRemainingView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        return HStack {
            Text(format(duration: trackFetcher.totalDuration))
            Text(string(forTime: trackFetcher.completionTime))
        }
    }
}


// used on the iPad
public struct BigButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    let onScan: () -> Void
    let onGoOffline: () -> Void

    public init(trackFetcher: TrackFetcher,
                onScan: @escaping () -> Void,
                onGoOffline: @escaping () -> Void)
    {
        self.trackFetcher = trackFetcher
        self.onScan = onScan
        self.onGoOffline = onGoOffline
    }

    public var body: some View {
        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })

        return
          VStack(alignment: .leading) {
              HStack {
                  SkipCurrentTrackButton(trackFetcher: self.trackFetcher)

                  if(self.trackFetcher.audioPlayer.isPaused) {
                      PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
                  } else {
                      PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
                  }

                  if trackFetcher.totalDuration > 0 {
                      VerticalPlayingTimeRemainingView(trackFetcher: trackFetcher)
                  }

                  PlayRandomTrackButton(trackFetcher: trackFetcher)
                  PlayNewRandomTrackButton(trackFetcher: trackFetcher)
                  ShuffleQueueButton(trackFetcher: trackFetcher)
                  // grouped to stay within SwiftUI's 10-view ViewBuilder limit
                  Group {
                      PlayUntilButton(trackFetcher: trackFetcher)
                      PlayForButton(trackFetcher: trackFetcher)
                      TrackVolumeButton(trackFetcher: trackFetcher)
                  }
                  Button(action: {
                       self.trackFetcher.cacheQueue()
                   }) {
                      Text("Cache Q")
                        .underline().foregroundColor(Color.blue)
                  }
                  ClearQueueButton(trackFetcher: trackFetcher)
              }
              HStack {
                  /*
                   Button(action: {
                   self.trackFetcher.clearCache()
                   }) {
                   Text("Clear Cache")
                   .underline().foregroundColor(Color.red)
                   }
                   */
                  OfflineScanButton(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)

                  MasterVolumeControl(trackFetcher: trackFetcher)

                  Group {
                      if !trackFetcher.useLocalContentOnly {
                          VStack {
                              HStack {
                                  Text("Play Local:")
                                  Toggle("", isOn: localPlayToggle).labelsHidden()
                              }
                          }
                      }

                      RefreshTracksFromServerButton(trackFetcher: trackFetcher)
                      RefreshQueueButton(trackFetcher: trackFetcher)

                      Spacer()
                  }
              }
          }
    }
}

public struct SmallButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    let onScan: () -> Void
    let onGoOffline: () -> Void
    @State private var showingActionSheet = false
    @State private var showingPlayUntilPicker = false
    @State private var showingPlayForPicker = false
    @State private var showingVolumePicker = false
    @State private var playUntilTime = Date()
    @State private var playForHours = 1
    @State private var playForMinutes = 0

    public init(trackFetcher: TrackFetcher,
                onScan: @escaping () -> Void,
                onGoOffline: @escaping () -> Void)
    {
        self.trackFetcher = trackFetcher
        self.onScan = onScan
        self.onGoOffline = onGoOffline
    }

  public var body: some View {
        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })
        let volumeLabel = volumeGainLabel(trackFetcher.currentTrackGainDB).map { "Set Volume…  (\($0))" } ?? "Set Volume…"
        return VStack {

                HStack {
                    Text("Actions")
                      .underline().foregroundColor(Color.blue)
                      .onTapGesture { self.showingActionSheet = true }
                      .actionSheet(isPresented: $showingActionSheet) {
                          ActionSheet(title: Text(""),
                                      buttons: [
                                        .default(Text("Play New Random Track")) { self.trackFetcher.playNewRandomTrack() },
                                        .default(Text("Play Random Track")) { self.trackFetcher.playRandomTrack() },
                                        .default(Text("Play Until…")) {
                                            self.playUntilTime = Date().addingTimeInterval(3600)
                                            self.showingPlayUntilPicker = true
                                        },
                                        .default(Text("Play For…")) {
                                            self.playForHours = 1
                                            self.playForMinutes = 0
                                            self.showingPlayForPicker = true
                                        },
                                        .default(Text(volumeLabel)) { self.showingVolumePicker = true },
                                        .default(Text("Refresh Queue")) { self.trackFetcher.refreshQueue() },
                                        .default(Text("Refresh Tracks")) { self.trackFetcher.refreshTracks() },
                                        .default(Text("Cache Current Queue")) { self.trackFetcher.cacheQueue() },
                                        .destructive(Text("Clear Cache")) { self.trackFetcher.clearCache() },
                                        .destructive(Text("Clear Queue")) { self.trackFetcher.clearPlayingQueue() },
                                        .cancel()
                                      ])
                      }
                    OfflineScanButton(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)
                }
                .sheet(isPresented: $showingPlayUntilPicker) {
                    VStack(spacing: 24) {
                        Text("Play Until").font(.headline)
                        DatePicker("", selection: $playUntilTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.wheel)
                        HStack {
                            Button("Cancel") { showingPlayUntilPicker = false }
                            Spacer()
                            Button("Confirm") {
                                trackFetcher.playUntil(date: playUntilTime)
                                showingPlayUntilPicker = false
                            }
                            .bold()
                        }
                    }
                    .padding()
                }

                HStack {
                    SkipCurrentTrackButton(trackFetcher: self.trackFetcher)

                    if(self.trackFetcher.playingQueue?.isPaused ?? false) {
                        PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
                    } else {
                        PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
                    }

                    if !trackFetcher.useLocalContentOnly {
                        VStack {
                            HStack {
                                Text("Play Local:")
                                Toggle("", isOn: localPlayToggle).labelsHidden()
                            }
                        }
                    }
                }

                MasterVolumeControl(trackFetcher: trackFetcher)

                HStack {
                    Spacer()
                    if trackFetcher.totalDuration > 0 {
                        HorizontalPlayingTimeRemainingView(trackFetcher: trackFetcher)
                    }
                }
        }
        .sheet(isPresented: $showingPlayForPicker) {
            VStack(spacing: 24) {
                Text("Play For").font(.headline)
                HStack(spacing: 0) {
                    Picker("Hours", selection: $playForHours) {
                        ForEach(0...23, id: \.self) { h in Text("\(h)h").tag(h) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                    Picker("Minutes", selection: $playForMinutes) {
                        ForEach(0...59, id: \.self) { m in Text("\(m)m").tag(m) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                }
                HStack {
                    Button("Cancel") { showingPlayForPicker = false }
                    Spacer()
                    Button("Confirm") {
                        let duration = TimeInterval(playForHours * 3600 + playForMinutes * 60)
                        trackFetcher.playUntil(date: Date().addingTimeInterval(duration))
                        showingPlayForPicker = false
                    }
                    .bold()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingVolumePicker) {
            TrackVolumeSheet(trackFetcher: trackFetcher, isPresented: $showingVolumePicker)
        }
    }
}

public struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    let onScan: () -> Void
    let onGoOffline: () -> Void

    public init(_ client: Client,
                onScan: @escaping () -> Void,
                onGoOffline: @escaping () -> Void)
    {
        self.trackFetcher = client.trackFetcher
        self.onScan = onScan
        self.onGoOffline = onGoOffline
    }

    public var body: some View {

        VStack(alignment: .leading) {
            if layoutIsLarge() {
                BigButtonView(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)
            } else {
                SmallButtonView(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)
            }
            PlayingTrackView(trackFetcher: trackFetcher)
            PlayingQueueView(trackFetcher: trackFetcher)
        }
    }
}



