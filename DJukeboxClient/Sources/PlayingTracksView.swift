import SwiftUI
import DJukeboxCommon

#if os(macOS)
fileprivate let kkUTTypePlainText = kUTTypePlainText
#else
fileprivate let kkUTTypePlainText = "kUTTypePlainText"
#endif

public func layoutIsLarge() -> Bool {
    #if os(iOS)// || os(watchOS) || os(tvOS)
    if UIDevice.current.userInterfaceIdiom == .pad {
        return true
    }else{
        return false
    }
    #elseif os(OSX)
    return true
    #else
    return false
    #endif
}

public struct PlayingTimeRemainingView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        VStack {
            Text(self.format(duration: trackFetcher.totalDuration))
            Text(self.string(forTime: trackFetcher.completionTime))
        }
    }
    func string(forTime date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .medium
        return dateFormatter.string(from: date)
    }
    
    func format(duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration/60) % 60
        let hours = Int(duration/(60*60))
        if hours > 0 {
            return "\(hours) hours"
        } else if minutes > 0 {
            return "\(minutes) minutes"
        } else {
            return "\(seconds) seconds"
        }
    }
}


    #if os(iOS)
    fileprivate let canStoreLocally = true
    #else
    fileprivate let canStoreLocally = false
    #endif
    
public struct BigButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        let offlineToggle = Binding<Bool>(get: { self.trackFetcher.useLocalContentOnly },
                                          set: { self.trackFetcher.useLocalContentOnly = $0 })

        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })

        return HStack {
            Spacer()

            if canStoreLocally {
                Button(action: {
                           self.trackFetcher.clearCache()
                       }) {
                    Text("Clear Cache")
                      .underline().foregroundColor(Color.red)
                }
                Button(action: {
                           self.trackFetcher.cacheQueue()
                       }) {
                    Text("Cache Queue")
                      .underline().foregroundColor(Color.blue)
                }
                Text("Offline:")
                Toggle("", isOn: offlineToggle).labelsHidden()
            }

                   
            VStack {
                HStack {
                    Text("Play Local:")
                    Toggle("", isOn: localPlayToggle).labelsHidden()
                }
            }
            
            SkipCurrentTrackButton(trackFetcher: self.trackFetcher)
            
            if(self.trackFetcher.audioPlayer.isPaused) {
                PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
            } else {
                PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
            }

            if trackFetcher.totalDuration > 0 {
                PlayingTimeRemainingView(trackFetcher: trackFetcher)
            }

            VStack {
                PlayRandomTrackButton(trackFetcher: trackFetcher)
                PlayNewRandomTrackButton(trackFetcher: trackFetcher)
            }
            ClearQueueButton(trackFetcher: trackFetcher)
            VStack {
                RefreshTracksFromServerButton(trackFetcher: trackFetcher)
                RefreshQueueButton(trackFetcher: trackFetcher)
            }
            Spacer()
        }
    }
}

#if os(iOS) 
public struct SmallButtonView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @State private var showingActionSheet = false
    
    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        let offlineToggle = Binding<Bool>(get: { self.trackFetcher.useLocalContentOnly },
                                          set: { self.trackFetcher.useLocalContentOnly = $0 })
        let localPlayToggle = Binding<Bool>(get: { self.trackFetcher.queueType == .local },
                                            set: { try? self.trackFetcher.watch(queue: $0 ? .local : .remote) })
        return VStack {

                HStack {
                    Text("Actions")
                      .underline().foregroundColor(Color.blue)
                      .onTapGesture { self.showingActionSheet = true }
                      .actionSheet(isPresented: $showingActionSheet) {
                          ActionSheet(title: Text(""),
                                      //message: Text(""),
                                      buttons: [
                                        .default(Text("Play New Random Track")) { self.trackFetcher.playNewRandomTrack() },
                                        .default(Text("Play Random Track")) { self.trackFetcher.playRandomTrack() },
                                        .default(Text("Refresh Queue")) { self.trackFetcher.refreshQueue() },
                                        .default(Text("Refresh Tracks")) { self.trackFetcher.refreshTracks() },
                                        .default(Text("Cache Current Queue")) { self.trackFetcher.cacheQueue() },
                                        .destructive(Text("Clear Cache")) { self.trackFetcher.clearCache() },
                                        .destructive(Text("Clear Queue")) { self.trackFetcher.clearPlayingQueue() },
                                        .cancel()
                                      ])
                      }
                    Text("Offline:")
                    Toggle("", isOn: offlineToggle).labelsHidden()
                }
                    
                HStack {
                    SkipCurrentTrackButton(trackFetcher: self.trackFetcher)
                    
                    if(self.trackFetcher.playingQueue?.isPaused ?? false) {
                        PlayButton(audioPlayer: self.trackFetcher.audioPlayer)
                    } else {
                        PauseButton(audioPlayer: self.trackFetcher.audioPlayer)
                    }

                    VStack {
                        HStack {
                            Text("Play Local:")
                            Toggle("", isOn: localPlayToggle).labelsHidden()
                        }
                    }
                }

                
                HStack {
                    Spacer()
                    if trackFetcher.totalDuration > 0 {
                        PlayingTimeRemainingView(trackFetcher: trackFetcher)
                    }
                }
        }
    }
}
#endif
    
public struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }
    
    let dropDelegate = MyDropDelegate(/*imageUrls: $imageUrls, active: $active*/)

    public var body: some View {
        
        VStack(alignment: .leading) {
            if layoutIsLarge() {
                BigButtonView(trackFetcher: trackFetcher)
            } else {
                #if os(iOS)
                SmallButtonView(trackFetcher: trackFetcher)
                #endif
            }
            HStack {
                Spacer()
                if trackFetcher.currentTrack == nil {
                    Text("Nothing Playing").foregroundColor(Color.gray)
                } else {
                    if layoutIsLarge() {
                        TrackDetail(track: trackFetcher.currentTrack!,
                                    trackFetcher: self.trackFetcher,
                                    showDuration: false,
                                    playOnTap: false)
                          .layoutPriority(1.0)
                        
                        ProgressBar(state: self.trackFetcher.progressBarLevel ?? ProgressBar.State()) { amount in
                            if amount < 60 {
                                return "\(Int(amount)) seconds left"
                            } else {
                                let duration = Int(amount)
                                let seconds = String(format: "%02d", duration % 60)
                                let minutes = duration / 60
                                return "\(minutes):\(seconds) left"
                            }
                        }
                          .layoutPriority(0.1)
                          .frame(maxWidth: .infinity, maxHeight: 20)
                    } else {
                        VStack {
                            ProgressBar(state: self.trackFetcher.progressBarLevel ?? ProgressBar.State()) { amount in
                                if amount < 60 {
                                    return "\(Int(amount)) seconds left"
                                } else {
                                    let duration = Int(amount)
                                    let seconds = String(format: "%02d", duration % 60)
                                    let minutes = duration / 60
                                    return "\(minutes):\(seconds) left"
                                }
                            }
                              .layoutPriority(0.1)
                              .frame(maxWidth: .infinity, maxHeight: 40)

                            TrackDetail(track: trackFetcher.currentTrack!,
                                        trackFetcher: self.trackFetcher,
                                        showDuration: false,
                                        playOnTap: false)
                              .layoutPriority(1.0)
                            
                        }
                    }
                }
                Spacer()
            }
              .disabled(trackFetcher.currentTrack == nil)

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


