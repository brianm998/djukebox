//
//  PanelKind.swift
//  DJukeboxClient
//
//  The interchangeable UI elements of the macOS dockable-panel workspace.
//

#if os(macOS)
import Foundation

public enum PanelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // Raw value pinned to the pre-rename name ("bands") so window layouts saved
    // before the Band -> Artist rename still decode.
    case artists = "bands"
    case albums
    case songs
    case playingControls
    case playingList
    case allSearch
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .artists:          return "Artists"
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
        case .artists:          return "person.3"
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
/// artist, or a songs panel pinned to an album (nil album = the artist's
/// singles). Bound panels show their fixed content regardless of the window's
/// live browse selection; unbound panels follow the window's cascade.
public enum PanelBinding: Hashable, Sendable {
    case artist(String)
    case album(artist: String, album: String?)
}

extension PanelBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case artist, album
    }

    // Wire-compatible shape for `.album`: the inner key is still "band" (from
    // before the Band -> Artist rename) even though the Swift label is now
    // `artist`, so previously saved window layouts keep loading.
    private struct AlbumPayload: Codable {
        let band: String
        let album: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let artist = try container.decodeIfPresent(String.self, forKey: .artist) {
            self = .artist(artist)
            return
        }
        let payload = try container.decode(AlbumPayload.self, forKey: .album)
        self = .album(artist: payload.band, album: payload.album)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .artist(let value):
            try container.encode(value, forKey: .artist)
        case .album(let artist, let album):
            try container.encode(AlbumPayload(band: artist, album: album), forKey: .album)
        }
    }
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
