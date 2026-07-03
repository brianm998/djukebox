//
//  LayoutView.swift
//  DJukeboxClient
//
//  Recursively renders a LayoutNode tree: leaves become PanelContainers, splits
//  become resizable HStacks/VStacks with draggable neon dividers. All edits
//  (close, divider drag) are expressed as a new root tree bubbled up via onChange.
//

#if os(macOS)
import SwiftUI

public struct LayoutView: View {
    private let root: LayoutNode
    private let context: PanelContext
    private let onChange: (LayoutNode) -> Void

    public init(root: LayoutNode,
                context: PanelContext,
                onChange: @escaping (LayoutNode) -> Void) {
        self.root = root
        self.context = context
        self.onChange = onChange
    }

    public var body: some View {
        // The close/resize closures capture the latest `root` (re-created on every
        // render), so they always operate on the current tree.
        NodeView(node: root,
                 context: context,
                 onClose: { id in
                     if let updated = root.removingLeaf(id: id) { onChange(updated) }
                 },
                 onFractions: { fractions, splitID in
                     onChange(root.settingFractions(fractions, for: splitID))
                 })
    }
}

struct NodeView: View {
    let node: LayoutNode
    let context: PanelContext
    let onClose: (UUID) -> Void
    let onFractions: ([Double], UUID) -> Void

    var body: some View {
        switch node {
        case .leaf(let panel):
            PanelContainer(panel: panel, windowID: context.windowID, onClose: { onClose(panel.id) }) {
                context.makeView(panel, context.client(for: panel.kind))
            }
        case let .split(sid, axis, children, fractions):
            SplitView(splitID: sid, axis: axis, children: children, fractions: fractions,
                      context: context, onClose: onClose, onFractions: onFractions)
        }
    }
}

private struct SplitView: View {
    let splitID: UUID
    let axis: LayoutAxis
    let children: [LayoutNode]
    let fractions: [Double]
    let context: PanelContext
    let onClose: (UUID) -> Void
    let onFractions: ([Double], UUID) -> Void

    // Captured once at the start of a divider drag so incremental re-renders don't
    // move the baseline out from under the gesture.
    @State private var dragBaseline: [Double]?
    private let thickness: CGFloat = 6
    private let minFraction = 0.06

    var body: some View {
        GeometryReader { geo in
            let totalLen = axis == .horizontal ? geo.size.width : geo.size.height
            let content = max(1, totalLen - CGFloat(max(0, children.count - 1)) * thickness)
            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) { lanes(content: content) }
                } else {
                    VStack(spacing: 0) { lanes(content: content) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func lanes(content: CGFloat) -> some View {
        ForEach(Array(children.enumerated()), id: \.element.id) { pair in
            let i = pair.offset
            let len = childLength(i, content: content)
            NodeView(node: pair.element, context: context, onClose: onClose, onFractions: onFractions)
                .frame(width: axis == .horizontal ? len : nil,
                       height: axis == .vertical ? len : nil)
                .frame(maxWidth: axis == .horizontal ? nil : .infinity,
                       maxHeight: axis == .vertical ? nil : .infinity)
            if i < children.count - 1 {
                DJSplitHandle(axis: axis,
                              onDrag: { t in applyDrag(dividerIndex: i, translation: t, content: content) },
                              onEnded: { dragBaseline = nil })
            }
        }
    }

    private func childLength(_ i: Int, content: CGFloat) -> CGFloat {
        guard i < fractions.count else { return content / CGFloat(max(1, children.count)) }
        return max(0, CGFloat(fractions[i]) * content)
    }

    private func applyDrag(dividerIndex i: Int, translation: CGFloat, content: CGFloat) {
        guard content > 0, i + 1 < children.count else { return }
        if dragBaseline == nil { dragBaseline = fractions }
        guard let base = dragBaseline, i + 1 < base.count else { return }
        let deltaF = Double(translation / content)
        var left = base[i] + deltaF
        var right = base[i + 1] - deltaF
        if left < minFraction { right -= (minFraction - left); left = minFraction }
        if right < minFraction { left -= (minFraction - right); right = minFraction }
        var f = base
        f[i] = left
        f[i + 1] = right
        onFractions(f, splitID)
    }
}

private struct DJSplitHandle: View {
    let axis: LayoutAxis
    let onDrag: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)   // keep the full hit area interactive
            if axis == .horizontal { DJNeonVDivider() } else { DJNeonDivider() }
        }
        .frame(width: axis == .horizontal ? thickness : nil,
               height: axis == .vertical ? thickness : nil)
        .frame(maxWidth: axis == .horizontal ? nil : .infinity,
               maxHeight: axis == .vertical ? nil : .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { v in onDrag(axis == .horizontal ? v.translation.width : v.translation.height) }
                .onEnded { _ in onEnded() }
        )
    }

    private let thickness: CGFloat = 6
}
#endif
