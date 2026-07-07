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

    enum DragPayload {
        case move(panel: Panel, sourceWindowID: UUID)   // relocate an existing panel
        case create(panel: Panel)                       // insert a new (bound) panel
        case window(sourceWindowID: UUID)               // merge a whole window into another
    }

    @Published var payload: DragPayload?
    @Published var dropTarget: DropTarget?

    var isDragging: Bool { payload != nil }

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

    func beginMove(panel: Panel, sourceWindow: UUID) {
        payload = .move(panel: panel, sourceWindowID: sourceWindow)
    }

    func beginCreate(panel: Panel) {
        payload = .create(panel: panel)
    }

    func beginWindow(sourceWindow: UUID) {
        payload = .window(sourceWindowID: sourceWindow)
    }

    func update(screenPoint: CGPoint) {
        guard let payload, let controller = controller else {
            dropTarget = nil
            return
        }
        switch payload {
        case .move(let panel, _), .create(let panel):
            dropTarget = controller.computeDropTarget(screenPoint: screenPoint,
                                                      draggingPanelID: panel.id,
                                                      excludeWindow: nil,
                                                      leafFrames: leafFrames)
        case .window(let sourceWindowID):
            // Merging: can't drop onto the source window itself.
            dropTarget = controller.computeDropTarget(screenPoint: screenPoint,
                                                      draggingPanelID: nil,
                                                      excludeWindow: sourceWindowID,
                                                      leafFrames: leafFrames)
        }
        // Re-assert each tick (cursor-rect updates are suppressed mid-drag, so this
        // holds): grabbing hand when it'll dock, copy cursor when it'll open a new
        // window on the empty desktop.
        (dropTarget != nil ? NSCursor.closedHand : NSCursor.dragCopy).set()
    }

    func end(screenPoint: CGPoint) {
        NSCursor.arrow.set()
        defer { payload = nil; dropTarget = nil }
        guard let payload, let controller = controller else { return }
        switch payload {
        case .move(let panel, let sourceWindowID):
            if let target = dropTarget {
                controller.handleDrop(panel: panel, from: sourceWindowID, target: target)
            } else {
                controller.tearOutPanel(panel, fromWindow: sourceWindowID, at: screenPoint)
            }
        case .create(let panel):
            if let target = dropTarget {
                controller.handleCreate(panel, target: target)
            } else {
                controller.newWindow(root: .leaf(panel), at: screenPoint,
                                     size: NSSize(width: 340, height: 520))
            }
        case .window(let sourceWindowID):
            if let target = dropTarget {
                controller.handleMerge(sourceWindowID: sourceWindowID, target: target)
            }
            // dropped on the desktop or its own window → no-op
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
                Rectangle()
                    .fill(DJTheme.neonCyan.opacity(0.22))
                    .overlay(Rectangle()
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
