import SwiftUI
import DJukeboxCommon
import DJukeboxClient

// nonisolated(unsafe): kUTTypePlainText is an immutable CFString system constant;
// CFString isn't Sendable but this value is never mutated.
nonisolated(unsafe) fileprivate let kkUTTypePlainText = kUTTypePlainText

// Mirrors the iOS control: in offline mode (no server) it offers to "Scan" for
// one; while connected it shows "Local", which drops back to offline (cached
// tracks only). Going offline always forces local playback.
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

        return HStack {
            Spacer()

            // mode: play-local toggle (online only, since offline forces local) + offline/scan
            VStack {
                if !trackFetcher.useLocalContentOnly {
                    HStack {
                        Text("Play Local:")
                        Toggle("", isOn: localPlayToggle).labelsHidden()
                    }
                }
                OfflineScanButton(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)
            }

            SkipCurrentTrackButton(trackFetcher: self.trackFetcher)

            if(self.trackFetcher.audioPlayer.isPaused) {
                PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
            } else {
                PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
            }

            if trackFetcher.totalDuration > 0 {
                VerticalPlayingTimeRemainingView(trackFetcher: trackFetcher)
            }

            MasterVolumeControl(trackFetcher: trackFetcher)

            VStack {
                PlayRandomTrackButton(trackFetcher: trackFetcher)
                PlayNewRandomTrackButton(trackFetcher: trackFetcher)
            }

            // queue + cache controls (grouped to stay within the ViewBuilder limit)
            Group {
                ShuffleQueueButton(trackFetcher: trackFetcher)
                ClearQueueButton(trackFetcher: trackFetcher)

                VStack {
                    PlayUntilButton(trackFetcher: trackFetcher)
                    PlayForButton(trackFetcher: trackFetcher)
                    TrackVolumeButton(trackFetcher: trackFetcher)
                }

                VStack {
                    // download the current playing queue for offline playback
                    Button(action: { self.trackFetcher.cacheQueue() }) {
                        Text("Cache Q").underline().foregroundColor(Color.blue)
                    }
                    // wipe the local track cache
                    Button(action: { self.trackFetcher.clearCache() }) {
                        Text("Clear Cache").underline().foregroundColor(Color.red)
                    }
                }

                VStack {
                    RefreshTracksFromServerButton(trackFetcher: trackFetcher)
                    RefreshQueueButton(trackFetcher: trackFetcher)
                }
            }
            Spacer()
        }
        /*

         // XXX this shit doesn't work on macosx 

          .contextMenu {
              Button(action:  {
                  Log.d("one")
              }) {
                  Text("one")
              }
              Text("Fuck")
              Button(action:  {
                  Log.d("two")
              }) {
                  Text("two")
              }
          }
*/
    }
}
    
public struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    let onScan: () -> Void
    let onGoOffline: () -> Void

    public init(_ client: Client,
                onScan: @escaping () -> Void = {},
                onGoOffline: @escaping () -> Void = {})
    {
        self.trackFetcher = client.trackFetcher
        self.onScan = onScan
        self.onGoOffline = onGoOffline
    }

    let dropDelegate = MyDropDelegate(/*imageUrls: $imageUrls, active: $active*/)

    public var body: some View {
        VStack(alignment: .leading) {
            BigButtonView(trackFetcher: trackFetcher, onScan: onScan, onGoOffline: onGoOffline)
            PlayingTrackView(trackFetcher: trackFetcher)
            PlayingQueueView(trackFetcher: trackFetcher)
              .onDrop(of: [kkUTTypePlainText as String], delegate: dropDelegate)
            
            /*
              .onDrop(of: [kkUTTypePlainText as String], isTargeted: nil) { providers in
                  for provider in providers {
                      Log.d("fuck \(provider.registeredTypeIdentifiers())")
                      if provider.hasItemConformingToTypeIdentifier(kkUTTypePlainText as String) {
                          Log.d("FUCK YES")
                          provider.loadItem(forTypeIdentifier: kkUTTypePlainText as String) { item, error in
                              Log.d("got item \(item) error \(error)")
                          }
                      } else {
                          Log.d("FUCK NO")
                      }
                      
                      provider.loadObject(ofClass: String.self) { string,two  in
                          Log.d("woot! \(string) \(two)")
                      }

                  }
                  return false
              }
*/
        }
    }
}

struct MyDropDelegate: DropDelegate {
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [kkUTTypePlainText as String])
    }
    
    func dropEntered(info: DropInfo) {
        Log.d("dropEntered")
        //NSSound(named: "Morse")?.play()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        Log.d("performDrop")
        //NSSound(named: "Submarine")?.play()
        
        //let gridPosition = getGridPosition(location: info.location)
        //self.active = gridPosition
        
        if let item = info.itemProviders(for: [kkUTTypePlainText as String]).first {
            item.loadItem(forTypeIdentifier: kkUTTypePlainText as String, options: nil) { (urlData, error) in
                //DispatchQueue.main.async {
                Log.d("UrlData \(urlData)")
                    if let urlData = urlData as? String {
                        Log.d("FUCK: \(urlData)")
                    } else {
                        Log.d("FAILED1")
                    }
            //}
            }

            
            return true
            
        } else {
            Log.d("FAILED")
            return false
        }
    }
}


