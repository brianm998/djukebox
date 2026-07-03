//
//  PanelContainer.swift
//  DJukeboxClient
//
//  Themed chrome around one panel leaf: a neon title bar (also the drag handle for
//  dock / tear-out) with a close button, over the panel content, wrapped in a
//  neon-bordered card. Reports its on-screen frame to the drag session so drops
//  can be targeted.
//

#if os(macOS)
import SwiftUI
import AppKit

public struct PanelContainer<Content: View>: View {
    @EnvironmentObject private var dragSession: PanelDragSession

    private let panel: Panel
    private let windowID: UUID
    private let onClose: () -> Void
    private let content: () -> Content

    public init(panel: Panel,
                windowID: UUID,
                onClose: @escaping () -> Void,
                @ViewBuilder content: @escaping () -> Content) {
        self.panel = panel
        self.windowID = windowID
        self.onClose = onClose
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            DJNeonDivider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .djCard(padding: 0)
        .background(frameReporter)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Image(systemName: panel.kind.systemImage)
                .font(.caption)
                .foregroundColor(DJTheme.textSecondary)
            Text(panel.kind.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DJTheme.neonGradientHorizontal)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DJTheme.textSecondary)
                    .padding(3)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DJTheme.panel.opacity(0.6))
        .contentShape(Rectangle())
        // Drag the title bar to dock this panel elsewhere (edge = split, center =
        // swap, another window = move) or onto the empty desktop (= new window).
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { _ in
                    if dragSession.dragging == nil {
                        dragSession.begin(panel: panel, sourceWindow: windowID)
                    }
                    dragSession.update(screenPoint: NSEvent.mouseLocation)
                }
                .onEnded { _ in
                    dragSession.end(screenPoint: NSEvent.mouseLocation)
                }
        )
    }

    private var frameReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { report(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { report($0) }
        }
    }

    private func report(_ rect: CGRect) {
        dragSession.reportLeafFrame(window: windowID, leaf: panel.id, rect: rect)
    }
}
#endif
