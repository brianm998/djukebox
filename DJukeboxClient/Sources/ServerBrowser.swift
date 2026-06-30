import Foundation
import Network
import CryptoKit
import DJukeboxCommon

// The states a ServerBrowser moves through while finding and connecting to a server.
public enum ServerConnectionState {
    case searching              // looking for a server on the local network
    case connecting             // found one, resolving / verifying it
    case connected(Client)      // ready to use
    case failed(String)         // gave up; the string is a human readable reason
}

/*
 Discovers a DJukebox server on the local network via mDNS / Bonjour rather than
 relying on a hardcoded IP address.

 It browses for the `_djukebox._tcp` service the server advertises, resolves the
 first match to a host and port, verifies the server actually answers, and only
 then builds a `Client`. Every step that can go wrong moves it to `.failed` with
 a message, so the UI can show something other than an empty view.
 */
public class ServerBrowser: ObservableObject {

    @Published public private(set) var state: ServerConnectionState = .searching

    // the live client once connected, handy for non-SwiftUI callers (e.g. key handlers)
    public private(set) var currentClient: Client?

    // whether the UI should offer an "offline mode" escape hatch (iOS opts in via
    // autoFallbackToLocal; the mac client, which has no offline mode, does not)
    public var allowsOfflineMode: Bool { autoFallbackToLocal }

    private let serviceType: String
    private let password: String
    private let initialQueueType: PlayingQueueType
    private let authHeaderValue: String
    private let searchTimeout: TimeInterval
    // when true, giving up on discovery drops into offline mode (local cache only)
    // instead of showing the failure screen. The iOS client opts in; the mac client doesn't.
    private let autoFallbackToLocal: Bool

    private var browser: NWBrowser?
    private var probe: NWConnection?
    private var hasResolved = false
    // bumped on every start()/retry() so stale async callbacks can be ignored
    private var generation = 0
    // the play-local choice from before we went offline, so a later scan can
    // restore it; nil means "no previous setting" (scan then defaults to remote)
    private var rememberedQueueType: PlayingQueueType?

    public init(serviceType: String = "_djukebox._tcp",
                password: String,
                initialQueueType: PlayingQueueType = .local,
                autoFallbackToLocal: Bool = false,
                searchTimeout: TimeInterval = 12.0)
    {
        self.serviceType = serviceType
        self.password = password
        self.initialQueueType = initialQueueType
        self.autoFallbackToLocal = autoFallbackToLocal
        self.searchTimeout = searchTimeout
        // same hashing the ServerConnection uses, so we can verify connectivity up front
        self.authHeaderValue = SHA512.hash(data: Data(password.utf8)).map {
            String(format: "%02hhx", $0)
        }.joined()
    }

    // Begin browsing the local network for a server.
    public func start() {
        cancelAll()
        generation += 1
        let gen = generation
        hasResolved = false
        DispatchQueue.main.async { self.state = .searching }

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] browserState in
            guard let self = self, gen == self.generation else { return }
            if case .failed(let error) = browserState {
                self.fail("Couldn't search the local network: \(error.localizedDescription)", gen: gen)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, gen == self.generation, !self.hasResolved else { return }
            guard let result = results.first else { return }
            self.hasResolved = true
            self.resolve(result.endpoint, gen: gen)
        }

        browser.start(queue: .main)

        // if nothing shows up in time, stop spinning and tell the user
        DispatchQueue.main.asyncAfter(deadline: .now() + searchTimeout) { [weak self] in
            guard let self = self, gen == self.generation else { return }
            if case .searching = self.state {
                self.fail("Couldn't find a DJukebox server on your WiFi network. "
                          + "Make sure the server is running on the same network.", gen: gen)
            }
        }
    }

    // Search again from scratch.
    public func retry() { start() }

    // Capture the current play-local choice before the client goes offline, so a
    // later scan/reconnect can put it back. No-op if we're already offline.
    public func rememberCurrentPlayLocal() {
        if let client = currentClient,
           !client.trackFetcher.useLocalContentOnly,
           let queueType = client.trackFetcher.queueType
        {
            rememberedQueueType = queueType
        }
    }

    // Stop searching and run from locally-cached tracks only (offline mode).
    // Used both as the automatic fallback when no server is found and when the
    // user explicitly chooses to go offline.
    public func goOffline() {
        cancelAll()
        generation += 1
        makeLocalClient(gen: generation)
    }

    // Build a client with no server, backed only by the local track cache.
    private func makeLocalClient(gen: Int) {
        guard gen == self.generation else { return }
        // An empty server URL means the (unused) server calls just fail quietly;
        // everything the client shows comes from the on-device cache instead.
        let client = Client(serverURL: "", password: self.password, initialQueueType: .local)
        try? client.trackFetcher.watch(queue: .local)  // offline always plays local
        client.trackFetcher.useLocalContentOnly = true
        self.currentClient = client
        self.state = .connected(client)
        Log.i("offline mode: no server found, playing locally cached tracks only")
    }

    // Bypass discovery and connect to a host the user typed in.
    public func connectManually(toHost host: String, port: Int) {
        cancelAll()
        generation += 1
        let gen = generation
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else {
            urlString = "http://\(trimmed):\(port)"
        }
        DispatchQueue.main.async { self.state = .connecting }
        verify(urlString: urlString, gen: gen)
    }

    // MARK: - private

    private func resolve(_ endpoint: NWEndpoint, gen: Int) {
        DispatchQueue.main.async { self.state = .connecting }

        // Connecting to the Bonjour endpoint resolves it to a concrete host/port.
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.probe = connection
        connection.stateUpdateHandler = { [weak self] connectionState in
            guard let self = self, gen == self.generation else { return }
            switch connectionState {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    let urlString = self.urlString(host: host, port: port)
                    connection.cancel()
                    self.probe = nil
                    self.verify(urlString: urlString, gen: gen)
                } else {
                    connection.cancel()
                    self.fail("Found a DJukebox server but couldn't resolve its address.", gen: gen)
                }
            case .failed(let error):
                connection.cancel()
                self.fail("Found a DJukebox server but couldn't connect: \(error.localizedDescription)", gen: gen)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func urlString(host: NWEndpoint.Host, port: NWEndpoint.Port) -> String {
        switch host {
        case .ipv4(let address):
            // a resolved address can carry an interface scope (e.g. "127.0.0.1%lo0"),
            // which is meaningless for IPv4 in a URL — drop it.
            return "http://\(stripZone("\(address)")):\(port.rawValue)"
        case .ipv6(let address):
            // IPv6 literals must be bracketed. A link-local zone id (%en0) is required
            // for routing and must be %25-encoded; for other addresses it's noise.
            var raw = "\(address)"
            if raw.lowercased().hasPrefix("fe80") {
                if let pct = raw.firstIndex(of: "%") {
                    raw.replaceSubrange(pct...pct, with: "%25")
                }
            } else {
                raw = stripZone(raw)
            }
            return "http://[\(raw)]:\(port.rawValue)"
        case .name(let name, _):
            return "http://\(stripZone(name)):\(port.rawValue)"
        @unknown default:
            return "http://\(host):\(port.rawValue)"
        }
    }

    // Remove an interface scope identifier ("192.168.1.5%en0" -> "192.168.1.5").
    private func stripZone(_ host: String) -> String {
        guard let pct = host.firstIndex(of: "%") else { return host }
        return String(host[..<pct])
    }

    // Confirm the server actually answers (and the password is accepted) before committing.
    private func verify(urlString: String, gen: Int) {
        guard let url = URL(string: "\(urlString)/tracks") else {
            self.fail("\(urlString) is not a valid server address.", gen: gen)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                if let error = error {
                    self.fail("Couldn't reach the DJukebox server: \(error.localizedDescription)", gen: gen)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self.fail("The DJukebox server refused the connection (HTTP \(http.statusCode)). "
                              + "Check the password.", gen: gen)
                    return
                }
                self.connect(toURL: urlString, gen: gen)
            }
        }.resume()
    }

    private func connect(toURL urlString: String, gen: Int) {
        guard gen == self.generation else { return }
        // were we offline (i.e. is this a scan/reconnect) before this connection?
        let reconnectingFromOffline = currentClient?.trackFetcher.useLocalContentOnly ?? false
        cancelAll()
        let client = Client(serverURL: urlString,
                            password: self.password,
                            initialQueueType: self.initialQueueType)
        // we reached a server, so use it: don't restore a stale offline preference
        if client.trackFetcher.useLocalContentOnly {
            client.trackFetcher.useLocalContentOnly = false
        }
        // coming back from offline via a scan: restore the play-local choice from
        // before we went offline, or default to not playing local if there was none
        if reconnectingFromOffline {
            try? client.trackFetcher.watch(queue: rememberedQueueType ?? .remote)
        }
        rememberedQueueType = nil
        self.currentClient = client
        self.state = .connected(client)
        Log.i("connected to DJukebox server at \(urlString)")
    }

    private func fail(_ reason: String, gen: Int) {
        DispatchQueue.main.async {
            guard gen == self.generation else { return }
            self.cancelAll()
            if self.autoFallbackToLocal {
                Log.i("server discovery failed (\(reason)); falling back to local")
                self.makeLocalClient(gen: gen)
                return
            }
            self.state = .failed(reason)
            Log.w("server discovery failed: \(reason)")
        }
    }

    private func cancelAll() {
        browser?.cancel(); browser = nil
        probe?.cancel(); probe = nil
    }
}
