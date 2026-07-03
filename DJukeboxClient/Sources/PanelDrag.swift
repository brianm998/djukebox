//
//  PanelDrag.swift
//  DJukeboxClient
//
//  Tear-out drag support for the macOS dockable panels. Dragging a row (artist /
//  album) or a panel title bar OUT of every window (onto the empty desktop)
//  spawns a new window. Detection is end-of-drag + NSEvent.mouseLocation vs the
//  open window frames — the only reliable way to notice a drop on empty space.
//
//  On iOS these are no-ops so the shared browse views still compile.
//

import SwiftUI

#if os(macOS)
import AppKit

// Injected into each workspace window's environment so the shared browse views
// can reach the window controller without the app target wiring each one.
struct PanelControllerKey: EnvironmentKey {
    static let defaultValue: PanelWindowController? = nil
}
public extension EnvironmentValues {
    var panelController: PanelWindowController? {
        get { self[PanelControllerKey.self] }
        set { self[PanelControllerKey.self] = newValue }
    }
}

// A long-press-then-drag so ordinary taps and List scrolling keep working; only a
// deliberate press-and-drag tears the row out to a new window.
private struct RowTearOut: ViewModifier {
    @Environment(\.panelController) private var controller
    let action: (PanelWindowController, CGPoint) -> Void

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 8, coordinateSpace: .global))
                .onEnded { _ in
                    if let controller = controller {
                        action(controller, NSEvent.mouseLocation)
                    }
                }
        )
    }
}

public extension View {
    /// Drag an artist row out → a new window showing that artist's albums.
    func artistTearOut(band: String) -> some View {
        modifier(RowTearOut { controller, point in
            controller.tearOutArtist(band: band, at: point)
        })
    }
    /// Drag an album row out → a new window showing that album's songs.
    func albumTearOut(band: String, album: String?) -> some View {
        modifier(RowTearOut { controller, point in
            controller.tearOutAlbum(band: band, album: album, at: point)
        })
    }
}
#else
public extension View {
    func artistTearOut(band: String) -> some View { self }
    func albumTearOut(band: String, album: String?) -> some View { self }
}
#endif
