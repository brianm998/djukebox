import SwiftUI
import DJukeboxClient
import DJukeboxCommon

public struct NaviTrackList: View {
    var client: Client
    // Observe the fetcher and derive the song list from the live catalog for this
    // artist/album, rather than freezing a snapshot at navigation time — otherwise a
    // catalog change (e.g. switching to local/offline) can't refresh this view.
    @ObservedObject var trackFetcher: TrackFetcher
    let album: AudioTrack   // representative track carrying the artist + album to show
    let title: String
    @State private var showingActionSheet = false
    @State private var showAllTracksToast: Bool = false
    @State private var showOneTrackToast: Bool = false
    @State private var fuck: String = ""

    public init(_ client: Client, album: AudioTrack, title: String) {
        self.client = client
        self.trackFetcher = client.trackFetcher
        self.album = album
        self.title = title
    }

    public var body: some View {
        let tracks = trackFetcher.tracks(for: album).sorted()
        return List(tracks) { track in
            Text(track.Title)
              .foregroundColor(DJTheme.textPrimary)
              .onTapGesture {
                  self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1) { track, error in
                      // XXX check error, etc here
                      if let track = track {
                        self.fuck = "\(track.Title) playing"
                          withAnimation { self.showOneTrackToast = true }
                      }
                  }
              }
        }
          .djListChrome()
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
                                self.trackFetcher.audioPlayer.player?.playTracks(tracks) { success, error in
                                    self.trackFetcher.refreshQueue()
                                    withAnimation { self.showAllTracksToast = true }
                                }
                            },
                            .default(Text("Cache All Locally")) {
                                self.trackFetcher.cache(tracks: tracks)
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
                        .fill(DJTheme.panel)
                        .overlay(Capsule().strokeBorder(DJTheme.neonGradient, lineWidth: 1.5))
                        .shadow(color: DJTheme.neonMagenta.opacity(0.5), radius: 6)

                    self.content()
                        .foregroundColor(DJTheme.textPrimary)
                } //ZStack (inner)
                .frame(width: geometry.size.width / 1.25, height: geometry.size.height / 10)
                .opacity(self.isPresented ? 1 : 0)
            } //ZStack (outer)
            .padding(.bottom)
        } //GeometryReader
    } //body
} //Toast

public extension View {
    func toast<Content>(isPresented: Binding<Bool>, content: @escaping () -> Content) -> some View where Content: View {
        Toast(
            isPresented: isPresented,
            presenter: { self },
            content: content
        )
    }
}
