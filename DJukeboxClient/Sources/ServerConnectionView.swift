import SwiftUI

/*
 Gates the real UI behind server discovery.

 While the ServerBrowser is searching or connecting it shows a status screen;
 when it gives up it shows a failure screen with a reason, a "Search Again"
 button, and a manual address entry, instead of the empty lists the app used to
 show. Once connected it hands the live Client to `content`.
 */
public struct ServerConnectionView<Content: View>: View {
    @ObservedObject private var browser: ServerBrowser
    private let content: (Client) -> Content

    public init(_ browser: ServerBrowser, @ViewBuilder content: @escaping (Client) -> Content) {
        self.browser = browser
        self.content = content
    }

    public var body: some View {
        switch browser.state {
        case .searching:
            ServerStatusView(glyph: "📡",
                             title: "Looking for DJukebox…",
                             message: "Searching your WiFi network for a DJukebox server.",
                             isBusy: true,
                             browser: browser)
        case .connecting:
            ServerStatusView(glyph: "📡",
                             title: "Connecting…",
                             message: "Found a DJukebox server, connecting to it.",
                             isBusy: true,
                             browser: browser)
        case .needsPairing(let pairing):
            PairingEntryView(pairing)
        case .failed(let reason):
            ServerStatusView(glyph: "⚠️",
                             title: "No DJukebox server found",
                             message: reason,
                             isBusy: false,
                             browser: browser)
        case .connected(let client):
            content(client)
        }
    }
}

struct ServerStatusView: View {
    let glyph: String
    let title: String
    let message: String
    let isBusy: Bool
    @ObservedObject var browser: ServerBrowser

    @State private var manualAddress: String = ""
    @State private var showManualEntry: Bool = false

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text(glyph)
                    .font(.system(size: 52))

                Text(title)
                    .font(.title)
                    .bold()
                    .foregroundColor(DJTheme.textPrimary)

                Text(message)
                    .font(.body)
                    .foregroundColor(DJTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)

                if isBusy {
                    busyIndicator

                    // let the user stop waiting and go offline when they know
                    // there's no server around (iOS only)
                    if browser.allowsOfflineMode {
                        Button("Offline Mode") { browser.goOffline() }
                            .buttonStyle(.bordered)
                            .tint(DJTheme.neonViolet)
                            .padding(.top)
                    }
                } else {
                    Button("Search Again") { browser.retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(DJTheme.neonViolet)

                    Button(showManualEntry ? "Hide manual entry" : "Enter address manually") {
                        showManualEntry.toggle()
                    }
                    .font(.footnote)

                    if showManualEntry {
                        HStack {
                            TextField("e.g. 192.168.1.10 or 192.168.1.10:8080", text: $manualAddress)
                                .textFieldStyle(.plain)
                                .djField()
                            Button("Connect", action: connectManually)
                                .buttonStyle(.borderedProminent)
                                .tint(DJTheme.neonViolet)
                                .disabled(manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .frame(maxWidth: 420)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
            .djCard(padding: 4)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var busyIndicator: some View {
        ProgressView()
    }

    private func connectManually() {
        let trimmed = manualAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // accept "host", "host:port", or a full "http://..." url
        var host = trimmed
        var port = 8080
        if !trimmed.lowercased().hasPrefix("http"),
           let colon = trimmed.lastIndex(of: ":"),
           let parsedPort = Int(trimmed[trimmed.index(after: colon)...]) {
            host = String(trimmed[..<colon])
            port = parsedPort
        }
        browser.connectManually(toHost: host, port: port)
    }
}
