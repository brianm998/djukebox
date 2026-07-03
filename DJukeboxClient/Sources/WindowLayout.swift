//
//  WindowLayout.swift
//  DJukeboxClient
//
//  Codable model for the whole macOS workspace: one WindowLayout per window
//  (its frame + panel tree), all held in a LayoutStore persisted to disk.
//

#if os(macOS)
import Foundation
import CoreGraphics

public struct WindowLayout: Codable, Identifiable, Sendable {
    public let id: UUID
    public var frame: CGRect
    public var root: LayoutNode

    public init(id: UUID = UUID(), frame: CGRect, root: LayoutNode) {
        self.id = id
        self.frame = frame
        self.root = root
    }
}

public struct LayoutStore: Codable, Sendable {
    public var windows: [WindowLayout]

    public init(windows: [WindowLayout]) { self.windows = windows }

    public static func load() -> LayoutStore? {
        guard let data = LayoutStorage.loadData(),
              let store = try? JSONDecoder().decode(LayoutStore.self, from: data)
        else { return nil }
        return store
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) { LayoutStorage.save(data) }
    }

    /// A fresh single-window workspace with the default panel arrangement.
    public static func defaultStore(frame: CGRect) -> LayoutStore {
        LayoutStore(windows: [WindowLayout(frame: frame, root: .defaultLayout())])
    }
}
#endif
