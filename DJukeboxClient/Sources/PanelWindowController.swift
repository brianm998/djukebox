//
//  PanelWindowController.swift
//  DJukeboxClient
//
//  Owns the macOS workspace windows for the dockable-panel UI. Replaces the old
//  ad-hoc `windows` array in TrackList: restores windows from the saved layout at
//  launch, spawns new ones (menu / tear-out), and persists the arrangement
//  (window frames + panel trees) as the user rearranges.
//

#if os(macOS)
import SwiftUI
import AppKit
import DJukeboxCommon

/// Per-window live layout state. The controller owns it; the window's SwiftUI
/// root observes it. Menu edits and drag edits both mutate `root`.
@MainActor
public final class PanelWindowModel: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var root: LayoutNode
    /// Last known frame (kept in sync from the window delegate for persistence).
    public var frame: CGRect
    /// One-shot browse seeding for torn-out artist/album windows (not persisted).
    public let seed: ((TrackFetcher) -> Void)?

    init(id: UUID, root: LayoutNode, frame: CGRect, seed: ((TrackFetcher) -> Void)?) {
        self.id = id
        self.root = root
        self.frame = frame
        self.seed = seed
    }
}

@MainActor
public final class PanelWindowController: NSObject, NSWindowDelegate {
    private let browser: ServerBrowser
    private let makeView: @MainActor (PanelKind, Client) -> AnyView
    private var models: [UUID: PanelWindowModel] = [:]
    private var windows: [UUID: NSWindow] = [:]
    private var saveWork: DispatchWorkItem?

    public private(set) weak var primaryWindow: NSWindow?

    public init(browser: ServerBrowser,
                makeView: @escaping @MainActor (PanelKind, Client) -> AnyView) {
        self.browser = browser
        self.makeView = makeView
        super.init()
    }

    public var isConnected: Bool { browser.currentClient != nil }

    // MARK: - Launch / reset

    public func restoreWindows() {
        let store = LayoutStore.load() ?? LayoutStore.defaultStore(frame: Self.defaultFrame())
        let toOpen = store.windows.isEmpty
            ? [WindowLayout(frame: Self.defaultFrame(), root: .defaultLayout())]
            : store.windows
        for layout in toOpen {
            openWindow(id: layout.id, root: layout.root.normalized(), frame: layout.frame, seed: nil)
        }
        primaryWindow = toOpen.first.flatMap { windows[$0.id] }
    }

    public func resetToDefault() {
        LayoutStorage.clear()
        for (_, window) in windows { window.delegate = nil; window.close() }
        windows.removeAll()
        models.removeAll()
        let layout = WindowLayout(frame: Self.defaultFrame(), root: .defaultLayout())
        openWindow(id: layout.id, root: layout.root, frame: layout.frame, seed: nil)
        primaryWindow = windows[layout.id]
        persist()
    }

    // MARK: - Window creation

    @discardableResult
    public func newWindow(root: LayoutNode,
                          at screenOrigin: CGPoint? = nil,
                          size: NSSize = NSSize(width: 900, height: 700),
                          seed: ((TrackFetcher) -> Void)? = nil) -> UUID {
        let id = UUID()
        var frame = Self.defaultFrame(size: size)
        if let origin = screenOrigin {
            frame.origin = CGPoint(x: origin.x, y: origin.y - size.height)
        }
        openWindow(id: id, root: root, frame: frame, seed: seed)
        persist()
        return id
    }

    private func openWindow(id: UUID, root: LayoutNode, frame: CGRect,
                            seed: ((TrackFetcher) -> Void)?) {
        let model = PanelWindowModel(id: id, root: root, frame: frame, seed: seed)
        models[id] = model

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "DJukebox"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        window.delegate = self

        let root = PanelWindowRoot(model: model, browser: browser, controller: self, makeView: makeView)
        window.contentView = NSHostingView(rootView: root)

        if frame.width < 120 || frame.height < 120 {
            window.setContentSize(NSSize(width: 900, height: 700))
            window.center()
        } else {
            window.setFrame(frame, display: false)
        }
        window.makeKeyAndOrderFront(nil)
        windows[id] = window
    }

    // MARK: - Edits (menu / UI)

    /// Add a panel to the key window (or the only window) and persist.
    public func addPanel(_ kind: PanelKind) {
        guard let model = keyModel() else { return }
        model.root = model.root.appending(Panel(kind))
        persist()
    }

    private func keyModel() -> PanelWindowModel? {
        if let raw = NSApp.keyWindow?.identifier?.rawValue,
           let id = UUID(uuidString: raw),
           let model = models[id] {
            return model
        }
        return models.values.first
    }

    // MARK: - Tear-out (drag a panel / artist / album out to a new window)

    private func isInsideAnyWindow(_ screenPoint: CGPoint) -> Bool {
        windows.values.contains { $0.frame.contains(screenPoint) }
    }

    /// Move a panel out of its window into a fresh window at the drop point. A
    /// drop that lands inside an existing window is left alone (in-window /
    /// cross-window docking is Milestone 2).
    public func tearOutPanel(_ panel: Panel, fromWindow windowID: UUID, at screenPoint: CGPoint) {
        guard !isInsideAnyWindow(screenPoint) else { return }
        guard let model = models[windowID] else { return }
        // If it's the only panel in the window, it already has its own window.
        guard let newRoot = model.root.removingLeaf(id: panel.id) else { return }
        model.root = newRoot
        newWindow(root: .leaf(Panel(panel.kind)), at: screenPoint,
                  size: NSSize(width: 380, height: 500))
    }

    /// New window showing an artist's albums.
    public func tearOutArtist(band: String, at screenPoint: CGPoint) {
        guard !isInsideAnyWindow(screenPoint) else { return }
        newWindow(root: .leaf(Panel(.albums)), at: screenPoint,
                  size: NSSize(width: 320, height: 520)) { fetcher in
            fetcher.shownAlbumsBand = band
            fetcher.albumTitle = band
        }
    }

    /// New window showing an album's songs (album may be nil for a band's singles).
    public func tearOutAlbum(band: String, album: String?, at screenPoint: CGPoint) {
        guard !isInsideAnyWindow(screenPoint) else { return }
        newWindow(root: .leaf(Panel(.songs)), at: screenPoint,
                  size: NSSize(width: 380, height: 520)) { fetcher in
            fetcher.desiredBand = band
            fetcher.desiredAlbum = album
            fetcher.trackTitle = album ?? "\(band) singles"
        }
    }

    // MARK: - Persistence

    public func persist() {
        saveWork?.cancel()
        let snapshot = models.values.map { model in
            WindowLayout(id: model.id,
                         frame: windows[model.id]?.frame ?? model.frame,
                         root: model.root)
        }
        let work = DispatchWorkItem { LayoutStore(windows: snapshot).save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windowID(window) else { return }
        window.delegate = nil
        windows[id] = nil
        models[id] = nil
        if primaryWindow == nil || primaryWindow == window {
            primaryWindow = windows.values.first
        }
        persist()
    }

    public func windowDidResize(_ notification: Notification) { syncFrame(notification); persist() }
    public func windowDidMove(_ notification: Notification) { syncFrame(notification); persist() }

    private func syncFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windowID(window) else { return }
        models[id]?.frame = window.frame
    }

    private func windowID(_ window: NSWindow) -> UUID? {
        guard let raw = window.identifier?.rawValue else { return nil }
        return UUID(uuidString: raw)
    }

    // MARK: - Helpers

    static func defaultFrame(size: NSSize = NSSize(width: 1000, height: 760)) -> CGRect {
        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            return CGRect(x: vis.midX - size.width / 2,
                          y: vis.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
        return CGRect(x: 100, y: 100, width: size.width, height: size.height)
    }
}
#endif
