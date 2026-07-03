//
//  LayoutStore.swift
//  DJukeboxClient
//
//  Tiny persistence primitive for the macOS dockable-panel layout. Stores opaque
//  Data so the (Codable) layout model can live in the app/panel layer without the
//  library depending on it. Mirrors PairingStore / RuntimeState: Codable JSON on
//  disk under ~/Library/.../State/, via LocalCache.
//

import Foundation
import DJukeboxCommon

public enum LayoutStorage {
    private static var url: URL? {
        LocalCache.urlForLibrary(appending: ["State"])?
          .appendingPathComponent("PanelLayout")
          .appendingPathExtension("json")
    }

    public static func loadData() -> Data? {
        guard let url = url else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func save(_ data: Data) {
        guard let url = url else { return }
        do {
            try data.write(to: url)
        } catch {
            Log.e("could not save panel layout: \(error)")
        }
    }

    public static func clear() {
        if let url = url { try? FileManager.default.removeItem(at: url) }
    }
}
