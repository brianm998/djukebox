import Foundation
import DJukeboxCommon

/*
 Advertises the running server on the local network via mDNS / Bonjour so that
 clients can discover it instead of using a hardcoded IP address.

 On macOS we use Foundation's NetService (no external dependencies).
 On Linux NetService publishing isn't reliable, so we shell out to
 avahi-publish-service (part of the avahi-utils package), matching the way the
 rest of the server shells out to platform tools (e.g. aplay).

 Why not Network.framework's NWListener (the modern, queue-driven successor to
 NetService used by the client's ServerBrowser/NWBrowser)? NWListener's normal
 model is to *own a real listening socket* — the port it advertises is the port
 it itself binds. Here the real HTTP listening socket already belongs to Vapor/
 SwiftNIO (see configure.swift, `app.http.server.configuration.port`); this
 class only needs to *announce* that already-bound port over mDNS, the way
 legacy NetService's `NetService(domain:type:name:port:)` does (it publishes
 PTR/SRV/TXT records for an arbitrary port without binding any socket itself).
 There is no public NWListener/NWParameters API to publish a service record for
 a port without the listener also binding it. Getting a second NWListener to
 bind Vapor's own port would require `NWParameters.allowLocalEndpointReuse`
 (SO_REUSEADDR/SO_REUSEPORT), and SO_REUSEPORT's actual kernel behavior for TCP
 is to load-balance *incoming SYNs* across every socket bound to that port —
 not to let one of them be a passive, traffic-free bystander. Even with no
 `newConnectionHandler` ever set on the NWListener side, some fraction of real
 client connection attempts aimed at Vapor would still be routed to the
 NWListener's socket by the kernel and silently stall/never accept, instead of
 reaching Vapor. That is a live-traffic-stealing regression risk, not a
 theoretical one, so NWListener is not used here; see docs/modernization-audit.md
 F24 for the fuller writeup of this decision.

 NetService itself has no Dispatch-queue-based scheduling API (only
 `scheduleInRunLoop(_:forMode:)` / `removeFromRunLoop(_:forMode:)` — confirmed
 by enumerating NSNetService's Objective-C method list; there is no
 queue/dispatch equivalent, unlike NWListener/NWBrowser which are queue-native).
 It fundamentally needs a live CFRunLoop, so a dedicated thread pumping its own
 run loop is still required and is kept below. What's modernized is everything
 around that unavoidable constraint: typed error reporting instead of a raw
 `[String: NSNumber]` dictionary.
 */
// @unchecked Sendable: a startup singleton. Its mutable handles (netService /
// thread / process) are set once when start() runs and not mutated concurrently.
public final class ServiceAdvertiser: NSObject, @unchecked Sendable {
    private let serviceName: String
    private let serviceType: String
    private let port: Int

#if os(Linux)
    private var process: Process?
#else
    private var netService: NetService?
    private var thread: Thread?
#endif

    /// - parameter type: a Bonjour service type, e.g. `_djukebox._tcp.`
    public init(name: String, type: String = "_djukebox._tcp.", port: Int) {
        self.serviceName = name
        self.serviceType = type
        self.port = port
    }

    public func start() {
#if os(Linux)
        startAvahi()
#else
        startNetService()
#endif
    }

#if os(Linux)
    private func startAvahi() {
        // avahi wants the type without a trailing dot
        var type = serviceType
        if type.hasSuffix(".") { type = String(type.dropLast()) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["avahi-publish-service", serviceName, type, "\(port)"]
        do {
            try process.run()
            self.process = process
            Log.i("advertising \(serviceName) (\(type)) on port \(port) via avahi-publish-service")
        } catch {
            Log.e("could not advertise via mDNS: \(error). Is avahi-utils installed (avahi-publish-service)?")
        }
    }
#else
    private func startNetService() {
        // NetService has no Dispatch-queue-based scheduling API (unlike
        // NWListener/NWBrowser) — only scheduleInRunLoop(_:forMode:) — so it
        // needs an actual CFRunLoop pumping somewhere. Vapor's async executor
        // doesn't guarantee RunLoop.main is serviced, so we still give
        // NetService its own thread + run loop rather than gamble on that.
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            let service = NetService(domain: "local.",
                                     type: self.serviceType,
                                     name: self.serviceName,
                                     port: Int32(self.port))
            service.delegate = self
            self.netService = service
            service.schedule(in: RunLoop.current, forMode: .common)
            service.publish()
            RunLoop.current.run()
        }
        thread.name = "djukebox-bonjour"
        self.thread = thread
        thread.start()
    }
#endif
}

#if !os(Linux)
// A typed stand-in for the legacy `[String: NSNumber]` errorDict
// NetServiceDelegate hands back, decoded from Apple's documented
// NetService.errorCode / NetService.errorDomain dictionary keys.
private struct NetServiceError: CustomStringConvertible {
    let domain: Int
    let code: Int

    init(_ errorDict: [String: NSNumber]) {
        self.domain = errorDict[NetService.errorDomain]?.intValue ?? 0
        self.code = errorDict[NetService.errorCode]?.intValue ?? 0
    }

    var description: String {
        "NetService error (domain: \(domain), code: \(code))"
    }
}

extension ServiceAdvertiser: NetServiceDelegate {
    public func netServiceDidPublish(_ sender: NetService) {
        Log.i("advertising Bonjour service \(sender.name) (\(sender.type)) on port \(sender.port)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Log.e("failed to advertise Bonjour service: \(NetServiceError(errorDict))")
    }
}
#endif
