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
              .foregroundColor((self.trackFetcher.cachedTrackSHA1s.contains(track.SHA1) ? CacheStatus.full : .none).color)
              .onTapGesture {
                  Task {
                      do {
                          let playedTrack = try await self.trackFetcher.audioPlayer.player?.playTrack(withHash: track.SHA1)
                          if let playedTrack = playedTrack {
                              self.fuck = "\(playedTrack.Title) playing"
                              withAnimation { self.showOneTrackToast = true }
                          }
                      } catch {
                          Log.e("could not play track: \(error)")
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
                                Menu {
                                    Button {
                                        Task {
                                            do {
                                                _ = try await self.trackFetcher.audioPlayer.player?.playTracks(tracks)
                                            } catch {
                                                Log.e("could not play all tracks: \(error)")
                                            }
                                            self.trackFetcher.refreshQueue()
                                            withAnimation { self.showAllTracksToast = true }
                                        }
                                    } label: {
                                        Label("Play All", systemImage: "play.fill")
                                    }
                                    Button {
                                        self.trackFetcher.cache(tracks: tracks)
                                    } label: {
                                        Label("Cache All Locally", systemImage: "arrow.down.circle")
                                    }
                                } label: {
                                    Image(systemName: "plus").imageScale(.large)
                                })
    }
}


struct Toast<Presenting, Content>: View where Presenting: View, Content: View {
    @Binding var isPresented: Bool
    let presenter: () -> Presenting
    let content: () -> Content
    let delay: TimeInterval = 2

    var body: some View {
        GeometryReader { geometry in
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
        .task(id: self.isPresented) {
            guard self.isPresented else { return }
            try? await Task.sleep(for: .seconds(self.delay))
            withAnimation {
                self.isPresented = false
            }
        }
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
