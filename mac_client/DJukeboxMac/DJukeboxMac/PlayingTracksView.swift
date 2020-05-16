import SwiftUI
import DJukeboxCommon
import DJukeboxClient

fileprivate let kkUTTypePlainText = kUTTypePlainText

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
                VerticalPlayingTimeRemainingView(trackFetcher: trackFetcher)
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
    
public struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(_ client: Client) {
        self.trackFetcher = client.trackFetcher
    }
    
    let dropDelegate = MyDropDelegate(/*imageUrls: $imageUrls, active: $active*/)

    public var body: some View {
        VStack(alignment: .leading) {
            BigButtonView(trackFetcher: trackFetcher)
            HStack {
                Spacer()
                if trackFetcher.currentTrack == nil {
                    Text("Nothing Playing").foregroundColor(Color.gray)
                } else {
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


