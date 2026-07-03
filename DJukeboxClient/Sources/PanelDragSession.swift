//
//  PanelDragSession.swift
//  DJukeboxClient
//
//  Live state for dragging a panel by its title bar (Milestone 2): tracks the
//  drag, records each leaf's on-screen frame, computes the current drop target
//  (which window / leaf / edge-or-center zone), and drives the drop indicator.
//  On drop it either docks (edge-split or center-swap, possibly cross-window) or,
//  when over the empty desktop, tears out to a new window.
//

#if os(macOS)
import SwiftUI
import AppKit

public enum DropZone: Equatable {
    case left, right, top, bottom, center
}

public struct DropTarget: Equatable {
    public let windowID: UUID
    public let leafID: UUID
    public let zone: DropZone
}

@MainActor
public final class PanelDragSession: ObservableObject {
    weak var controller: PanelWindowController?

    struct Dragging { let panel: Panel; let sourceWindowID: UUID }

    @Published var dragging: Dragging?
    @Published var dropTarget: DropTarget?

    /// leaf frames in SwiftUI global space, per window. Not @Published — it changes
    /// constantly during layout; the overlay reads it when `dropTarget` changes.
    private var leafFrames: [UUID: [UUID: CGRect]] = [:]

    public init() {}

    // MARK: leaf-frame registry

    func reportLeafFrame(window: UUID, leaf: UUID, rect: CGRect) {
        leafFrames[window, default: [:]][leaf] = rect
    }

    func removeWindow(_ window: UUID) {
        leafFrames[window] = nil
    }

    func frame(window: UUID, leaf: UUID) -> CGRect? {
        leafFrames[window]?[leaf]
    }

    // MARK: drag lifecycle

    func begin(panel: Panel, sourceWindow: UUID) {
        dragging = Dragging(panel: panel, sourceWindowID: sourceWindow)
    }

    func update(screenPoint: CGPoint) {
        guard let dragging = dragging, let controller = controller else {
            dropTarget = nil
            return
        }
        dropTarget = controller.computeDropTarget(screenPoint: screenPoint,
                                                  draggingPanelID: dragging.panel.id,
                                                  leafFrames: leafFrames)
    }

    func end(screenPoint: CGPoint) {
        defer { dragging = nil; dropTarget = nil }
        guard let dragging = dragging, let controller = controller else { return }
        if let target = dropTarget {
            controller.handleDrop(panel: dragging.panel, from: dragging.sourceWindowID, target: target)
        } else {
            controller.tearOutPanel(dragging.panel, fromWindow: dragging.sourceWindowID, at: screenPoint)
        }
    }
}

// Draws the neon placement indicator over the hovered leaf of this window.
struct DropIndicatorOverlay: View {
    let windowID: UUID
    @EnvironmentObject var session: PanelDragSession

    var body: some View {
        GeometryReader { _ in
            if let target = session.dropTarget,
               target.windowID == windowID,
               let rect = session.frame(window: windowID, leaf: target.leafID) {
                let ind = indicatorRect(rect, target.zone)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DJTheme.neonCyan.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DJTheme.neonCyan, lineWidth: 2))
                    .frame(width: max(1, ind.width), height: max(1, ind.height))
                    .position(x: ind.midX, y: ind.midY)
                    .animation(.easeOut(duration: 0.08), value: target)
            }
        }
        .allowsHitTesting(false)
    }

    private func indicatorRect(_ r: CGRect, _ zone: DropZone) -> CGRect {
        switch zone {
        case .center: return r
        case .left:   return CGRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height)
        case .right:  return CGRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height)
        case .top:    return CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2)
        case .bottom: return CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2)
        }
    }
}
#endif
