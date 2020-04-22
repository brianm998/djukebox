import SwiftUI

struct ButtonStack: View {

    @ObservedObject var serverConnection: ServerConnection //ServerType
    
    let buttonWidth: CGFloat = 80
    
    var body: some View {
        VStack {
            Button(action: {
                server.playRandomTrack() { audioTrack, error in
                    if let error = error {
                        print("DOH")
                    } else if let audioTrack = audioTrack {
                        print("enqueued: \(audioTrack.Title)")
                    }
                    trackFetcher.refreshQueue()
                }
            }) {
                Text("Random")
                  .frame(width: buttonWidth)
            }
            HStack {
                Button(action: {
                    server.stopAllTracks() { audioTrack, error in
                        if let error = error {
                            print("DOH")
                        } else {
                            print("enqueued: \(audioTrack)")
                        }
                        trackFetcher.refreshQueue()
                    }
                }) {
                    /*
                     "\u{25B6}" - play
                     "\u{23f8}" - pause
                     "\u{23F9}" - stop
                     */
                    Text("\u{23F9}").font(.largeTitle) // stop
                }.buttonStyle(PlainButtonStyle())
                Button(action: {
                    if server.isPaused {
                        server.resumePlaying() { audioTrack, error in
                            if let error = error {
                                print("DOH")
                            } else {
                                print("enqueued: \(audioTrack)")
                            }
                        }
                    } else {
                        server.pausePlaying() { audioTrack, error in
                            if let error = error {
                                print("DOH")
                            } else {
                                print("enqueued: \(audioTrack)")
                            }
                        }
                    }
                }) {
                    /*
                     "\u{25B6}" - play
                     "\u{23F8}" - pause
                     "\u{23F9}" - stop
                     */
                    Text(serverConnection.isPaused ? "\u{25B6}" : "\u{23F8}").font(.largeTitle) // play / pause
                    //Text("\u{23F8}").font(.largeTitle) // pause
                }.buttonStyle(PlainButtonStyle())
            }

            /*
            Button(action: {
                       server.pausePlaying() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                       }
                   }) {
                Text("Pause")
                  .frame(width: buttonWidth)
            }
            Button(action: {
                       server.resumePlaying() { audioTrack, error in
                           if let error = error {
                               print("DOH")
                           } else {
                               print("enqueued: \(audioTrack)")
                           }
                       }
                   }) {
                Text("Resume")
                  .frame(width: buttonWidth)
            }
*/
            Button(action: {
                trackFetcher.refreshTracks()
            }) {
                Text("Refresh")
                  .frame(width: buttonWidth)
            }
            Button(action: {
                trackFetcher.refreshQueue()
            }) {
                Text("Refresh Q")
                  .frame(width: buttonWidth)
            }
        }        
    }
}

