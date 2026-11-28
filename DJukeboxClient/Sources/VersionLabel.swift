import SwiftUI

/*
 One line saying which app version is running and, when there is a server to ask,
 that server's name and version.

 The server is asked when the label appears (and again if the server changes), so
 nothing is added to the connect or Client startup paths.
 */
public struct VersionLabel: View {
    private let server: ServerType?
    @State private var serverInfo: ServerVersionInfo?

    public init(server: ServerType? = nil) {
        self.server = server
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DJTheme.textSecondary)
            .lineLimit(1)
            .task(id: server?.url ?? "") {
                serverInfo = nil
                guard let server, server.hasServer else { return }
                // purely informational: on failure just show the app version
                serverInfo = try? await server.serverVersion()
            }
    }

    private var text: String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        var parts = ["App \(appVersion ?? "unknown")"]
        if let serverInfo {
            parts.append("Server: \(serverInfo.name) \(serverInfo.version)")
        }
        return parts.joined(separator: " · ")
    }
}
