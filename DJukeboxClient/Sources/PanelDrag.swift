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

// A plain click-drag on the row drives the shared drag session (like a panel
// title-bar drag) so it gets the live drop indicator and can dock into a window
// (edge/center) or, on the empty desktop, open a new window. macOS lists don't
// drag-to-scroll, so a plain DragGesture is safe here; the small minimumDistance
// keeps ordinary clicks (which still fire the row's onTapGesture) working.
private struct RowDrag: ViewModifier {
    @Environment(\.panelController) private var controller
    /// The bound panel this row represents.
    let makePanel: () -> Panel

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { _ in
                    guard let session = controller?.dragSession else { return }
                    if !session.isDragging { session.beginCreate(panel: makePanel()) }
                    session.update(screenPoint: NSEvent.mouseLocation)
                }
                .onEnded { _ in
                    controller?.dragSession.end(screenPoint: NSEvent.mouseLocation)
                }
        )
    }
}

public extension View {
    /// Drag an artist row → dock (or open) an albums panel scoped to that artist.
    func artistTearOut(band: String) -> some View {
        modifier(RowDrag { Panel(.albums, binding: .artist(band)) })
    }
    /// Drag an album row → dock (or open) a songs panel scoped to that album.
    func albumTearOut(band: String, album: String?) -> some View {
        modifier(RowDrag { Panel(.songs, binding: .album(band: band, album: album)) })
    }
}
#else
public extension View {
    func artistTearOut(band: String) -> some View { self }
    func albumTearOut(band: String, album: String?) -> some View { self }
}
#endif
