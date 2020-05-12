import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviTrackList: View {
    var client: Client
    let tracks: [AudioTrack]
    let title: String
    @State private var showingActionSheet = false
    @State private var showAllTracksToast: Bool = false
    @State private var showOneTrackToast: Bool = false
    @State private var fuck: String = ""
    
    public init(_ client: Client, tracks: [AudioTrack], title: String) {
        self.client = client
        self.tracks = tracks
        self.title = title
    }

    public var body: some View {
        List(self.tracks) { track in
            Text(track.Title)
              .onTapGesture {
                  self.client.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { track, error in
                      // XXX check error, etc here
                      if let track = track {
                        self.fuck = "\(track.Title) playing"
                          withAnimation { self.showOneTrackToast = true }
                      } 
                  }
              }
        }
          .toast(isPresented: $showOneTrackToast) {
              Text(self.fuck)
          }
          .toast(isPresented: $showAllTracksToast) {
              Text("All tracks playing")
          }
          .navigationBarTitle(Text(title), displayMode: .inline)
          .navigationBarItems(trailing:
                                Button(action: {self.showingActionSheet = true }) {
                                    Image(systemName: "plus").imageScale(.large)
                                })
          .actionSheet(isPresented: $showingActionSheet) {
              ActionSheet(title: Text(""),
                          buttons: [
                            .default(Text("Play All")) {
                                self.client.trackFetcher.audioPlayer.player?.playTracks(self.tracks.sorted()) { success, error in
                                    self.client.trackFetcher.refreshQueue()
                                    withAnimation { self.showAllTracksToast = true }
                                }
                            },
                            .default(Text("Cache All Locally")) {
                                self.client.trackFetcher.cache(tracks: self.tracks)
                            },
                            .cancel()
                          ]
              )
          }
    }
}


struct Toast<Presenting, Content>: View where Presenting: View, Content: View {
    @Binding var isPresented: Bool
    let presenter: () -> Presenting
    let content: () -> Content
    let delay: TimeInterval = 2

    var body: some View {
        if self.isPresented {
            DispatchQueue.main.asyncAfter(deadline: .now() + self.delay) {
                withAnimation {
                    self.isPresented = false
                }
            }
        }

        return GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                self.presenter()

                ZStack {
                    Capsule()
                        .fill(Color.gray)

                    self.content()
                } //ZStack (inner)
                .frame(width: geometry.size.width / 1.25, height: geometry.size.height / 10)
                .opacity(self.isPresented ? 1 : 0)
            } //ZStack (outer)
            .padding(.bottom)
        } //GeometryReader
    } //body
} //Toast

extension View {
    func toast<Content>(isPresented: Binding<Bool>, content: @escaping () -> Content) -> some View where Content: View {
        Toast(
            isPresented: isPresented,
            presenter: { self },
            content: content
        )
    }
}
