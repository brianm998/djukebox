import SwiftUI

public struct ProgressBar: View {
    public class State: ObservableObject {
        public init(level: Double = 0, max: Double = 1) {
            self.level = level
            self.max = max
        }
        @Published var level: Double // 0..max
        @Published var max: Double
    }

    public init(state: ProgressBar.State, labelClosure: ((Double) -> String)?) {
        self.state = state
        self.labelClosure = labelClosure
    }
    
    @ObservedObject public var state: ProgressBar.State
    var labelClosure: ((Double) -> String)?
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().frame(width: geometry.size.width,
                                  height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(Color.gray)

                Rectangle().frame(width: min(CGFloat(self.state.level/self.state.max)*geometry.size.width,
                                             geometry.size.width),
                                  height: geometry.size.height)
                  .foregroundColor(Color.green)
                  .animation(.linear)

                if self.labelClosure != nil && self.state.level > 0 {
                    Text(self.labelClosure!(self.state.max-self.state.level))
                      .offset(x: 8)
                      .foregroundColor(Color.gray)
                      .opacity(0.7)
                }
            }.cornerRadius(8)
        }
    }
}

