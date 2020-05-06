import SwiftUI

struct ProgressBar: View {
    @ObservedObject var trackFetcher: TrackFetcher
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().frame(width: geometry.size.width,
                                  height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(Color.gray)

                // XXX This sucks to have the track fetcher so deeply imbedded here
                Rectangle().frame(width: min(CGFloat(self.trackFetcher.playingTrackProgress ?? 0)*geometry.size.width,
                                             geometry.size.width),
                                  height: geometry.size.height)
                  .foregroundColor(Color.green)
                  .animation(.linear)

                if self.trackFetcher.totalDuration > 0 {
                    Text(self.remainingTimeText(self.trackFetcher.currentTrackRemainingTime))
                      .offset(x: 8)
                      .foregroundColor(Color.gray)
                      .opacity(0.7)
                }
            }.cornerRadius(8)
        }
    }

    private func remainingTimeText(_ amount: TimeInterval) -> String {
        if amount < 60 {
            return "\(Int(amount)) seconds left"
        } else {
            let duration = Int(amount)
            let seconds = String(format: "%02d", duration % 60)
            let minutes = duration / 60
            return "\(minutes):\(seconds) left"
        }
    }
}

