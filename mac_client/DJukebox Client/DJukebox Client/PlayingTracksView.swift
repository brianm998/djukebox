import SwiftUI

struct PlayingTracksView: View {
    @ObservedObject var trackFetcher: TrackFetcher
    @ObservedObject var audioPlayer: ViewObservableAudioPlayer

    let dropDelegate = MyDropDelegate(/*imageUrls: $imageUrls, active: $active*/)

    let buttonWidth: CGFloat = 80
    
    var body: some View {
        
        VStack(alignment: .leading) {
            HStack {
                Spacer()

                SkipCurrentTrackButton(trackFetcher: self.trackFetcher,
                                       audioPlayer: self.audioPlayer)
                
                if(self.audioPlayer.isPaused) {
                    PlayButton(audioPlayer: self.audioPlayer)
                } else {
                    PauseButton(audioPlayer: self.audioPlayer)
                }

                if trackFetcher.totalDuration > 0 {
                    Text(self.format(duration: trackFetcher.totalDuration))
                    Text(self.string(forTime:trackFetcher.completionTime))
                }

                PlayRandomTrackButton(trackFetcher: trackFetcher,
                                      audioPlayer: self.audioPlayer,
                                      buttonWidth: buttonWidth)

                PlayNewRandomTrackButton(trackFetcher: trackFetcher,
                                      audioPlayer: self.audioPlayer,
                                      buttonWidth: buttonWidth)
                
                ClearQueueButton(trackFetcher: trackFetcher,
                                 audioPlayer: self.audioPlayer,
                                 buttonWidth: buttonWidth)

                RefreshTracksFromServerButton(trackFetcher: trackFetcher,
                                              buttonWidth: buttonWidth)

                RefreshQueueButton(trackFetcher: trackFetcher,
                                   buttonWidth: buttonWidth)
            }
            
            HStack {
                Spacer()
                if trackFetcher.currentTrack == nil {
                    Text("Nothing Playing").foregroundColor(Color.gray)
                } else {
                    TrackDetail(track: trackFetcher.currentTrack!,
                                trackFetcher: self.trackFetcher,
                                audioPlayer: self.audioPlayer,
                                showDuration: false,
                                playOnTap: false)

                            /*
                    CurrentTrackView(track: trackFetcher.currentTrack!,
                                     trackFetcher: self.trackFetcher,
                                     audioPlayer: self.audioPlayer)
*/
                      .layoutPriority(1.0)
                    ProgressBar(trackFetcher: trackFetcher)
                      .layoutPriority(0.1)
                      .frame(maxWidth: .infinity, maxHeight: 20)
                }
                Spacer()
            }
              .disabled(trackFetcher.currentTrack == nil)

            PlayingQueueView(trackFetcher: trackFetcher, audioPlayer: self.audioPlayer)
              .onDrop(of: [kUTTypePlainText as String], delegate: dropDelegate)
            
            /*
              .onDrop(of: [kUTTypePlainText as String], isTargeted: nil) { providers in
                  for provider in providers {
                      print("fuck \(provider.registeredTypeIdentifiers())")
                      if provider.hasItemConformingToTypeIdentifier(kUTTypePlainText as String) {
                          print("FUCK YES")
                          provider.loadItem(forTypeIdentifier: kUTTypePlainText as String) { item, error in
                              print("got item \(item) error \(error)")
                          }
                      } else {
                          print("FUCK NO")
                      }
                      
                      provider.loadObject(ofClass: String.self) { string,two  in
                          print("woot! \(string) \(two)")
                      }

                  }
                  return false
              }
*/
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

struct MyDropDelegate: DropDelegate {
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [kUTTypePlainText as String])
    }
    
    func dropEntered(info: DropInfo) {
        print("dropEntered")
        //NSSound(named: "Morse")?.play()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        print("performDrop")
        //NSSound(named: "Submarine")?.play()
        
        //let gridPosition = getGridPosition(location: info.location)
        //self.active = gridPosition
        
        if let item = info.itemProviders(for: [kUTTypePlainText as String]).first {
            item.loadItem(forTypeIdentifier: kUTTypePlainText as String, options: nil) { (urlData, error) in
                //DispatchQueue.main.async {
                print("UrlData \(urlData)")
                    if let urlData = urlData as? String {
                        print("FUCK: \(urlData)")
                    } else {
                        print("FAILED1")
                    }
            //}
            }

            
            return true
            
        } else {
            print("FAILED")
            return false
        }
    }
}


