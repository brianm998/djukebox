import Foundation
import Combine
import DJukeboxCommon
#if os(iOS)
import UIKit
#endif

/*
 The client side of device pairing.

  - PairingStore    persists this device's bearer token across launches.
  - PairingClient    drives the *new device* side of the handshake (request a
                     pairing, wait for approval, claim a token with the code).
  - PairingMonitor   drives the *approver* side on an already-trusted client
                     (poll for incoming requests, approve/deny, show the code).

 See the server's PairingService / PairingController for the matching endpoints.
 */

// MARK: - persisted token

public enum PairingStore {
    private struct Stored: Codable { let token: String }

    private static var url: URL? {
        LocalCache.urlForLibrary(appending: ["State"])?
          .appendingPathComponent("Pairing")
          .appendingPathExtension("json")
    }

    /// The token for the jukebox this device is paired with, or nil if unpaired.
    public static func load() -> String? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }
        return stored.token
    }

    public static func save(_ token: String) {
        guard let url else { return }
        do {
            try JSONEncoder().encode(Stored(token: token)).write(to: url)
        } catch {
            Log.e("could not save pairing token: \(error)")
        }
    }

    public static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// A friendly default name for this device, shown in the pair request.
    @MainActor
    public static var defaultDeviceName: String {
#if os(iOS)
        return UIDevice.current.name
#else
        return Host.current().localizedName ?? "Mac"
#endif
    }
}

// MARK: - wire types

private struct PairRequestResponse: Decodable { let requestId: String }
private struct PairStatusResponse: Decodable { let state: String }
private struct PairApproveResponse: Decodable { let code: String }
private struct PairClaimResponse: Decodable { let outcome: String; let token: String? }

/// One request waiting to be approved, as shown to a trusted client.
public struct PendingPairRequest: Decodable, Identifiable, Equatable {
    public let requestId: String
    public let name: String
    public let createdAt: Double
    public var id: String { requestId }
}

// MARK: - new-device side

/*
 Runs on the device that wants in. start() announces the intent and then polls
 for approval; once approved the UI collects the 6-digit code and calls
 submit(code:). On success the token is persisted and `onPaired` fires so the
 ServerBrowser can build a real Client.
 */
// @MainActor: a UI state machine (new-device pairing). Its URLSession completions
// and poll timer already marshal every @Published mutation to the main thread.
@MainActor
public class PairingClient: ObservableObject {

    public enum Phase: Equatable {
        case requesting         // sending the initial request
        case waiting            // waiting for someone to approve
        case readyForCode       // approved — enter the code shown on the other device
        case submitting         // claiming with the entered code
        case denied             // a trusted client rejected us
        case paired             // done
        case failed(String)     // request/claim couldn't complete
    }

    @Published public private(set) var phase: Phase = .requesting
    // a transient note shown under the input (e.g. "that code didn't match")
    @Published public var note: String?

    public let serverURL: String
    public var deviceName: String

    private let onPaired: (String) -> Void
    private var requestId: String?
    private var pollTask: Task<Void, Never>?
    private let session = URLSession.shared

    public init(serverURL: String,
                deviceName: String = PairingStore.defaultDeviceName,
                onPaired: @escaping (String) -> Void)
    {
        self.serverURL = serverURL
        self.deviceName = deviceName
        self.onPaired = onPaired
    }

    deinit { pollTask?.cancel() }

    /// Announce the intent to pair and begin polling for approval.
    public func start() {
        setPhase(.requesting)
        note = nil
        guard let url = URL(string: "\(serverURL)/pair/request"),
              let body = try? JSONEncoder().encode(["name": deviceName]) else {
            setPhase(.failed("Couldn't contact the server."))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        request.timeoutInterval = 15
        Task { @MainActor in
            do {
                let (data, _) = try await session.data(for: request)
                guard let decoded = try? JSONDecoder().decode(PairRequestResponse.self, from: data) else {
                    self.setPhase(.failed("The server didn't accept the pairing request."))
                    return
                }
                self.requestId = decoded.requestId
                self.setPhase(.waiting)
                self.startPolling()
            } catch {
                self.setPhase(.failed("Couldn't reach the server: \(error.localizedDescription)"))
            }
        }
    }

    /// Exchange the code the user read off the trusted device for a token.
    public func submit(code: String) {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6, let requestId = requestId else {
            note = "Enter the 6-digit code."
            return
        }
        setPhase(.submitting)
        note = nil
        guard let url = URL(string: "\(serverURL)/pair/claim"),
              let body = try? JSONEncoder().encode(["requestId": requestId, "code": digits]) else {
            setPhase(.failed("Couldn't contact the server."))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        request.timeoutInterval = 15
        Task { @MainActor in
            do {
                let (data, _) = try await session.data(for: request)
                guard let decoded = try? JSONDecoder().decode(PairClaimResponse.self, from: data) else {
                    self.note = "Unexpected response from the server."
                    self.setPhase(.readyForCode)
                    return
                }
                switch decoded.outcome {
                case "paired":
                    if let token = decoded.token {
                        PairingStore.save(token)
                        self.stopPolling()
                        self.setPhase(.paired)
                        self.onPaired(token)
                    } else {
                        self.note = "The server didn't return a token."
                        self.setPhase(.readyForCode)
                    }
                case "wrongCode":
                    self.note = "That code didn't match. Try again."
                    self.setPhase(.readyForCode)
                case "notApproved":
                    self.note = "Not approved yet — waiting for the other device."
                    self.setPhase(.waiting)
                case "denied":
                    self.stopPolling()
                    self.setPhase(.denied)
                default:
                    self.stopPolling()
                    self.setPhase(.failed("This pairing request expired. Try again."))
                }
            } catch {
                self.note = "Couldn't reach the server: \(error.localizedDescription)"
                self.setPhase(.readyForCode)
            }
        }
    }

    /// Start over with a fresh request (after a denial or failure).
    public func retry() {
        stopPolling()
        requestId = nil
        start()
    }

    public func cancel() { stopPolling() }

    // MARK: - polling

    private func startPolling() {
        stopPolling()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.pollStatus()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollStatus() {
        guard let requestId,
              let url = URL(string: "\(serverURL)/pair/status/\(requestId)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        Task { @MainActor in
            guard let (data, _) = try? await session.data(for: request),
                  let decoded = try? JSONDecoder().decode(PairStatusResponse.self, from: data) else { return }
            switch decoded.state {
            case "approved":
                // don't clobber the user mid-submit
                if self.phase == .waiting { self.setPhase(.readyForCode) }
            case "denied":
                self.stopPolling()
                self.setPhase(.denied)
            default:
                break // still "requested"
            }
        }
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
    }
}

// MARK: - approver side

/*
 Runs on an already-trusted client (loopback, or a paired device). Polls the
 server for pending pair requests so the user can allow or deny them; on allow,
 the server returns the 6-digit code to show. This is how the server "tells" all
 paired clients that someone wants to pair.
 */
// @MainActor: a UI state machine (approver side). Its URLSession completions and
// poll timer already marshal every @Published mutation to the main thread.
@MainActor
public class PairingMonitor: ObservableObject {

    @Published public private(set) var pending: [PendingPairRequest] = []
    // set after approving: the request name + the code to display to the user
    @Published public var activeCode: (name: String, code: String)?

    private let serverURL: String
    private let authHeaderValue: String
    private var pollTask: Task<Void, Never>?
    private let session = URLSession.shared
    // requests this device chose to ignore ("Not now") — hidden locally without
    // denying them for everyone else.
    private var ignoredIds: Set<String> = []

    public init(server: ServerType) {
        self.serverURL = server.url
        self.authHeaderValue = server.authHeaderValue
    }

    // deinit is nonisolated, so it can't call the @MainActor stop(); cancel the
    // task directly (matching PairingClient's deinit). Task is Sendable, unlike
    // Timer, so this needs no nonisolated(unsafe) escape hatch.
    deinit { pollTask?.cancel() }

    public func start() {
        // no point polling an offline/local client (it has no server)
        guard !serverURL.isEmpty else { return }
        stop()
        poll()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.poll()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func approve(_ request: PendingPairRequest) {
        post("pair/approve", body: ["requestId": request.requestId],
             decodeAs: PairApproveResponse.self) { [weak self] response in
            guard let self else { return }
            if let response {
                self.activeCode = (name: request.name, code: response.code)
            }
            self.poll()
        }
    }

    public func deny(_ request: PendingPairRequest) {
        // /pair/deny returns an empty 200; we don't care about the body, just re-poll.
        post("pair/deny", body: ["requestId": request.requestId],
             decodeAs: PairApproveResponse.self) { [weak self] _ in
            self?.poll()
        }
    }

    /// Dismiss the displayed code once the user is done reading it.
    public func clearCode() { activeCode = nil }

    /// Hide a request on this device only (don't approve or deny it for others).
    public func ignore(_ request: PendingPairRequest) {
        ignoredIds.insert(request.requestId)
        pending.removeAll { $0.requestId == request.requestId }
    }

    // MARK: - networking

    private func poll() {
        guard let url = URL(string: "\(serverURL)/pair/pending") else { return }
        var request = URLRequest(url: url)
        request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        Task { @MainActor in
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode([PendingPairRequest].self, from: data) else { return }
            // forget ignores for requests the server no longer lists
            let liveIds = Set(decoded.map { $0.requestId })
            self.ignoredIds = self.ignoredIds.intersection(liveIds)
            self.pending = decoded.filter { !self.ignoredIds.contains($0.requestId) }
        }
    }

    private func post<T: Decodable & Sendable>(_ path: String,
                                    body: [String: String],
                                    decodeAs: T.Type,
                                    closure: @escaping (T?) -> Void)
    {
        guard let url = URL(string: "\(serverURL)/\(path)"),
              let payload = try? JSONEncoder().encode(body) else {
            closure(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = payload
        request.timeoutInterval = 15
        Task { @MainActor in
            guard let (data, _) = try? await session.data(for: request) else {
                closure(nil)
                return
            }
            closure(try? JSONDecoder().decode(T.self, from: data))
        }
    }
}
