import SwiftUI

// shows the currently playing track with a progress bar
public struct PlayingTrackView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }

    public var body: some View {
        return VStack {
            if trackFetcher.currentTrack == nil {
                Text("Nothing Playing").foregroundStyle(Color.gray)
            } else {
                HStack {
                    //            Spacer()
                    ZStack(alignment: .leading) {
                        
                        ProgressBar(state: self.trackFetcher.progressBarLevel ?? ProgressBar.State()) { amount in
                            guard let seconds = Int(exactly: amount.rounded(.towardZero)) else { return "" }
                            if amount < 60 {
                                return "\(seconds) seconds left"
                            } else {
                                return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)) + " left"
                            }
                        }
                        //                  .layoutPriority(0.1)
                          .frame(maxWidth: .infinity, maxHeight: 40)


                        TrackDetail(track: trackFetcher.currentTrack!,
                                    trackFetcher: self.trackFetcher,
                                    showDuration: false,
                                    playOnTap: false)
                          .offset(x: 8)
                        
                        //                  .layoutPriority(1.0)
                        
                    }
                }
            }
            //              .disabled(trackFetcher.currentTrack == nil)
            //            Spacer()
        }
    }
}
