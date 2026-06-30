import Foundation
import DJukeboxCommon

/*
 Advertises the running server on the local network via mDNS / Bonjour so that
 clients can discover it instead of using a hardcoded IP address.

 On macOS we use Foundation's NetService (no external dependencies).
 On Linux NetService publishing isn't reliable, so we shell out to
 avahi-publish-service (part of the avahi-utils package), matching the way the
 rest of the server shells out to platform tools (e.g. aplay).
 */
public final class ServiceAdvertiser: NSObject {
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
        // NetService needs a running run loop, so publish it on its own thread.
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
extension ServiceAdvertiser: NetServiceDelegate {
    public func netServiceDidPublish(_ sender: NetService) {
        Log.i("advertising Bonjour service \(sender.name) (\(sender.type)) on port \(sender.port)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Log.e("failed to advertise Bonjour service: \(errorDict)")
    }
}
#endif
