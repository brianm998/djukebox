import Foundation
import Network
import DJukeboxCommon

// The states a ServerBrowser moves through while finding and connecting to a server.
public enum ServerConnectionState {
    case searching                  // looking for a server on the local network
    case connecting                 // found one, resolving / verifying it
    case needsPairing(PairingClient)// reached a server over WiFi but this device isn't paired
    case connected(Client)          // ready to use
    case failed(String)             // gave up; the string is a human readable reason
}

/*
 Discovers a DJukebox server and connects to it.

 Two ways in:
  - Loopback first (the mac client): a daemon running on this same machine is
    reachable at 127.0.0.1 and trusts loopback without pairing. We probe it first
    and, if it answers, connect immediately.
  - Bonjour discovery (always on iOS, and the fallback on mac): browse for the
    `_djukebox._tcp` service the server advertises, resolve it, and connect. A
    server reached this way is on the WiFi, so it requires a pairing token. If this
    device has a stored token we use it; otherwise (or if the server rejects it) we
    drop into the pairing flow instead of failing.

 Every step that can go wrong moves to `.failed` with a message so the UI can show
 something other than an empty view.
 */
// @MainActor: a UI state machine driving @Published `state`. The NWBrowser/NWConnection
// handlers are started with queue: .main, so they run on the main thread at runtime, but
// the compiler still sees them as plain nonisolated @Sendable closures — Swift 6 doesn't
// treat "queue: .main" as proof of main-actor isolation, so each handler hops back in via
// `Task { @MainActor in ... }` (a same-thread, immediate resumption in practice, not a
// dispatch queue round trip) rather than assuming isolation lines up. The loopback/verify
// probes use async URLSession.data(for:), which resumes its awaiting Task on the main
// actor here since the whole class (and therefore every Task { ... } it spawns) is
// @MainActor.
@MainActor
public class ServerBrowser: ObservableObject {

    @Published public private(set) var state: ServerConnectionState = .searching

    // the live client once connected, handy for non-SwiftUI callers (e.g. key handlers)
    public private(set) var currentClient: Client?

    // whether the UI should offer an "offline mode" escape hatch (iOS opts in via
    // autoFallbackToLocal; the mac client, which has no offline mode, does not)
    public var allowsOfflineMode: Bool { autoFallbackToLocal }

    private let serviceType: String
    private let initialQueueType: PlayingQueueType
    private let searchTimeout: TimeInterval
    // when true, giving up on discovery drops into offline mode (local cache only)
    // instead of showing the failure screen. The iOS client opts in; the mac client doesn't.
    private let autoFallbackToLocal: Bool
    // when true, probe a same-machine daemon at 127.0.0.1 before browsing the WiFi
    // (the mac client). Loopback is trusted by the server without pairing.
    private let tryLoopbackFirst: Bool
    private let loopbackPort: Int

    // the token the server trusts for loopback connections (content is ignored by
    // the server for loopback peers, but the streaming path needs a non-empty value)
    private static let loopbackToken = "local"

    private var browser: NWBrowser?
    private var probe: NWConnection?
    private var hasResolved = false
    // bumped on every start()/retry() so stale async callbacks can be ignored
    private var generation = 0
    // the play-local choice from before we went offline, so a later scan can
    // restore it; nil means "no previous setting" (scan then defaults to remote)
    private var rememberedQueueType: PlayingQueueType?
    // strong ref to the in-flight pairing client (state also holds it, but keep it
    // here so it survives any transient state changes)
    private var pairingClient: PairingClient?

    public init(serviceType: String = "_djukebox._tcp",
                initialQueueType: PlayingQueueType = .local,
                autoFallbackToLocal: Bool = false,
                tryLoopbackFirst: Bool = false,
                loopbackPort: Int = 8080,
                searchTimeout: TimeInterval = 12.0)
    {
        self.serviceType = serviceType
        self.initialQueueType = initialQueueType
        self.autoFallbackToLocal = autoFallbackToLocal
        self.tryLoopbackFirst = tryLoopbackFirst
        self.loopbackPort = loopbackPort
        self.searchTimeout = searchTimeout
    }

    // Begin finding a server: probe loopback first (if enabled), then browse WiFi.
    public func start() {
        cancelAll()
        generation += 1
        let gen = generation
        hasResolved = false
        state = .searching

        if tryLoopbackFirst {
            probeLoopback(gen: gen)
        } else {
            startBonjour(gen: gen)
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
        let client = Client(serverURL: "", token: Self.loopbackToken, initialQueueType: .local)
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
        state = .connecting
        verify(urlString: urlString, gen: gen)
    }

    // MARK: - loopback

    // Probe a daemon on this machine. On success connect immediately (loopback is
    // trusted, no pairing); on any failure fall back to Bonjour discovery.
    private func probeLoopback(gen: Int) {
        let urlString = "http://127.0.0.1:\(loopbackPort)"
        // /queue: same auth gate as everything else, tiny body (/tracks would
        // download the entire catalog just to learn the status code)
        guard let url = URL(string: "\(urlString)/queue") else {
            startBonjour(gen: gen)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0   // keep the fall-through to WiFi snappy
        Task { [weak self] in
            guard let self = self else { return }
            var response: URLResponse?
            do {
                (_, response) = try await URLSession.shared.data(for: request)
            } catch {
                response = nil
            }
            guard gen == self.generation else { return }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                Log.i("found a local daemon at 127.0.0.1:\(self.loopbackPort)")
                self.connect(toURL: urlString, token: Self.loopbackToken, gen: gen)
            } else {
                Log.i("no local daemon; browsing the WiFi for a server")
                self.startBonjour(gen: gen)
            }
        }
    }

    // MARK: - Bonjour discovery

    private func startBonjour(gen: Int) {
        guard gen == self.generation else { return }
        state = .searching

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        self.browser = browser

        // NWBrowser delivers these on .main, so at runtime this is an immediate
        // same-thread resumption, not a real dispatch hop — but the compiler still
        // requires an explicit hop back to the main actor (see the class doc comment).
        browser.stateUpdateHandler = { [weak self] browserState in
            Task { @MainActor in
                guard let self = self, gen == self.generation else { return }
                if case .failed(let error) = browserState {
                    self.fail("Couldn't search the local network: \(error.localizedDescription)", gen: gen)
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self = self, gen == self.generation, !self.hasResolved else { return }
                guard let result = results.first else { return }
                self.hasResolved = true
                self.resolve(result.endpoint, gen: gen)
            }
        }

        browser.start(queue: .main)

        // if nothing shows up in time, stop spinning and tell the user
        let timeout = searchTimeout
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self = self, gen == self.generation else { return }
            if case .searching = self.state {
                self.fail("Couldn't find a DJukebox server on your WiFi network. "
                          + "Make sure the server is running on the same network.", gen: gen)
            }
        }
    }

    private func resolve(_ endpoint: NWEndpoint, gen: Int) {
        state = .connecting

        // Connecting to the Bonjour endpoint resolves it to a concrete host/port.
        // Restrict the probe to IPv4: the server only listens on IPv4, but mDNS
        // also advertises the host's IPv6 link-local address, and letting the
        // probe try that first cost seconds of connect/reset fallback at startup
        // (and the address we extract here is what all later HTTP goes to).
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        self.probe = connection
        // delivered on .main, so at runtime this is an immediate same-thread
        // resumption, not a real dispatch hop — but the compiler still requires
        // an explicit hop back to the main actor (see the class doc comment).
        connection.stateUpdateHandler = { [weak self] connectionState in
            Task { @MainActor in
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
        }
        connection.start(queue: .main)

        // The searchTimeout watchdog only fires while state is .searching, and we
        // just moved to .connecting — a probe with no viable candidate (e.g. the
        // service resolves to no IPv4 address) sits in .preparing/.waiting forever
        // without ever reaching .failed. Give the probe its own deadline so
        // fail()'s offline fallback still happens. Reuse the browse-phase budget:
        // a working-but-slow connect (mDNS retransmit backoff on lossy WiFi, a
        // sleeping server waking on demand) can legitimately need well over 5s.
        let timeout = searchTimeout
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self = self, gen == self.generation, self.probe === connection else { return }
            connection.cancel()
            self.probe = nil
            self.fail("Found a DJukebox server but couldn't connect to it.", gen: gen)
        }
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

    // MARK: - verify / pair / connect

    // Confirm a WiFi server answers and that we're allowed in. Uses this device's
    // stored token if it has one. A 401 (or no token) means we need to pair.
    // /queue is gated by the same header auth as everything else but its response
    // is tiny — /tracks (used here previously) returned the entire multi-megabyte
    // catalog just to learn the status code, adding seconds to every startup.
    private func verify(urlString: String, gen: Int) {
        guard let url = URL(string: "\(urlString)/queue") else {
            self.fail("\(urlString) is not a valid server address.", gen: gen)
            return
        }
        let token = PairingStore.load()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 8.0
        Task { [weak self] in
            guard let self = self else { return }
            var response: URLResponse?
            do {
                (_, response) = try await URLSession.shared.data(for: request)
            } catch {
                guard gen == self.generation else { return }
                self.fail("Couldn't reach the DJukebox server: \(error.localizedDescription)", gen: gen)
                return
            }
            guard gen == self.generation else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), let token = token {
                // our stored token still works
                self.connect(toURL: urlString, token: token, gen: gen)
            } else if status == 401 || token == nil {
                // not paired (or token no longer accepted): start pairing
                self.beginPairing(urlString: urlString, gen: gen)
            } else {
                self.fail("The DJukebox server refused the connection (HTTP \(status)).", gen: gen)
            }
        }
    }

    // Hand off to the pairing flow. On success we build a real client with the new token.
    private func beginPairing(urlString: String, gen: Int) {
        guard gen == self.generation else { return }
        Log.i("not paired with \(urlString); starting pairing flow")
        let pairing = PairingClient(serverURL: urlString) { [weak self] token in
            guard let self = self, gen == self.generation else { return }
            self.connect(toURL: urlString, token: token, gen: gen)
        }
        self.pairingClient = pairing
        self.state = .needsPairing(pairing)
        pairing.start()
    }

    private func connect(toURL urlString: String, token: String, gen: Int) {
        guard gen == self.generation else { return }
        // were we offline (i.e. is this a scan/reconnect) before this connection?
        let reconnectingFromOffline = currentClient?.trackFetcher.useLocalContentOnly ?? false
        cancelAll()
        let client = Client(serverURL: urlString,
                            token: token,
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
        self.pairingClient = nil
        self.currentClient = client
        self.state = .connected(client)
        Log.i("connected to DJukebox server at \(urlString)")
    }

    private func fail(_ reason: String, gen: Int) {
        guard gen == self.generation else { return }
        cancelAll()
        if autoFallbackToLocal {
            Log.i("server discovery failed (\(reason)); falling back to local")
            makeLocalClient(gen: gen)
            return
        }
        state = .failed(reason)
        Log.w("server discovery failed: \(reason)")
    }

    private func cancelAll() {
        browser?.cancel(); browser = nil
        probe?.cancel(); probe = nil
    }
}
