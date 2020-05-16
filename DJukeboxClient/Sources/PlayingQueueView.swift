import SwiftUI
import DJukeboxCommon

public struct PlayingQueueView: View {
    @ObservedObject var trackFetcher: TrackFetcher

    public init(trackFetcher: TrackFetcher) {
        self.trackFetcher = trackFetcher
    }
    
    public var body: some View {
        List {
            ForEach(trackFetcher.pendingTracks, id: \.self) { track in
                TrackDetail(track: track,
                            trackFetcher: self.trackFetcher,
                            playOnTap: false)
            }
              .onDelete(perform: delete)
              .onMove(perform: move)
              //.onInsert(of: ["public.url"], perform: drop) // XXX doesn't work
        }
    }
    private func drop(at index: Int, _ items: [NSItemProvider]) {
        for item in items {
            _ = item.loadObject(ofClass: URL.self) { url, error in
                Log.d("url \(url) error \(error)")
                //DispatchQueue.main.async {
                    //url.map { self.links.insert($0, at: index) }
            //}
            }
        }
    }
    
    private func move(source: IndexSet, destination: Int) {
        let startIndex = source.sorted()[0]
        let endIndex = destination
        let trackToMove = trackFetcher.pendingTracks[startIndex]
        if startIndex < endIndex {
            let positionsAhead = endIndex-startIndex-1
            Log.d("moving track \(trackToMove.SHA1) up \(positionsAhead) positions from \(startIndex)")
            trackFetcher.audioPlayer.player?.movePlayingTrack(withHash: trackToMove.SHA1,
                                                              fromIndex: startIndex,
                                                              toIndex: startIndex + positionsAhead) { playingQueue, error in
                if let queue = playingQueue {
                    self.trackFetcher.update(playingQueue: queue)
                }
            }
        } else if startIndex > endIndex {
            let positionsBehind = startIndex-endIndex
            Log.d("moving track \(trackToMove.SHA1) down \(positionsBehind) positions from \(startIndex)")
            trackFetcher.audioPlayer.player?.movePlayingTrack(withHash: trackToMove.SHA1,
                                                              fromIndex: startIndex,
                                                              toIndex: startIndex - positionsBehind) { playingQueue, error in
                if let queue = playingQueue {
                    self.trackFetcher.update(playingQueue: queue)
                }
            }
        } else {
            Log.d("not moving at all")
        }
    }

    func delete (at offsets: IndexSet) {
        Log.d("delete @ \(offsets)")

        offsets.forEach { index in
            Log.d("index \(index)")
            trackFetcher.removeItemFromPlayingQueue(at: index)
        }
    }

}

