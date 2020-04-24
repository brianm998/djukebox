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
                    Text("Clear Queue")
                   //   .font(.largeTitle)
                      .foregroundColor(Color.red)
                }
            }

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

