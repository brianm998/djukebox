//
//  PanelContainer.swift
//  DJukeboxClient
//
//  Themed chrome around one panel leaf: a neon title bar (which is also the drag
//  handle for tear-out) with a close button, over the panel content, wrapped in a
//  neon-bordered card.
//

#if os(macOS)
import SwiftUI
import AppKit

public struct PanelContainer<Content: View>: View {
    @Environment(\.panelController) private var controller

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
        // Drag the title bar onto the empty desktop → new window with this panel.
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onEnded { _ in
                    controller?.tearOutPanel(panel, fromWindow: windowID, at: NSEvent.mouseLocation)
                }
        )
    }
}
#endif
