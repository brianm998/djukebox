//
//  PanelKind.swift
//  DJukeboxClient
//
//  The interchangeable UI elements of the macOS dockable-panel workspace.
//

#if os(macOS)
import Foundation

public enum PanelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bands
    case albums
    case songs
    case playingControls
    case playingList
    case allSearch
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bands:           return "Bands"
        case .albums:          return "Albums"
        case .songs:           return "Songs"
        case .playingControls: return "Controls"
        case .playingList:     return "Queue"
        case .allSearch:       return "Search"
        case .history:         return "History"
        }
    }

    public var systemImage: String {
        switch self {
        case .bands:           return "person.3"
        case .albums:          return "square.stack"
        case .songs:           return "music.note.list"
        case .playingControls: return "play.circle"
        case .playingList:     return "list.number"
        case .allSearch:       return "magnifyingglass"
        case .history:         return "gobackward"
        }
    }
}

/// An optional fixed scope for a browse panel: an albums panel pinned to an
/// artist, or a songs panel pinned to an album (nil album = the band's singles).
/// Bound panels show their fixed content regardless of the window's live browse
/// selection; unbound panels follow the window's cascade.
public enum PanelBinding: Codable, Hashable, Sendable {
    case artist(String)
    case album(band: String, album: String?)
}

/// A single placed panel. Its `id` is stable across saves and drives SwiftUI
/// identity, the layout tree, and close/drag targeting. Duplicates are allowed:
/// two Panels with the same `kind` but different `id` are independent.
public struct Panel: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: PanelKind
    public var binding: PanelBinding?

    public init(_ kind: PanelKind, id: UUID = UUID(), binding: PanelBinding? = nil) {
        self.kind = kind
        self.id = id
        self.binding = binding
    }
}
#endif
