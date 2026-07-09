import Foundation
import SwiftUI
import DJukeboxCommon

public protocol ServerType: Sendable {
    func listTracks() async throws -> [AudioTrack]

    func listHistory() async throws -> PlayingHistory
    func listHistory(since: Int) async throws -> PlayingHistory
    func post(history: ServerHistoryEntry) async throws

    // persist / read the per-track/album/artist playback gains the server applies
    func setVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws
    func clearVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws
    func listVolumeAdjustments() async throws -> [VolumeAdjustment]
    // the saved gain (dB) for a track, for pre-filling the volume control; nil
    // means there is no adjustment on record (not an error)
    func savedGain(forHash hash: String) async throws -> Double?

    // the global master gain (dB, <= 0), applied on top of every per-track gain;
    // nil means no master gain has been set on the server yet (not an error)
    func masterGain() async throws -> Double?
    func setMasterGain(_ decibels: Double) async throws

    var authHeaderValue: String { get }
    var url: String { get }

    // True when there is a real server to talk to. The offline / local-only
    // client is built with an empty server URL (see ServerBrowser.makeLocalClient),
    // for which this is false; callers must then skip server round-trips rather
    // than firing requests that can only fail.
    var hasServer: Bool { get }
}

public enum ServerConnectionError: Error {
    // Thrown instead of hitting the network when the client has no server
    // (offline / local-only mode, i.e. an empty server URL). Callers that guard
    // on `hasServer` never see this; it's the safety net for any path that
    // reaches a networking call offline, replacing the opaque
    // URLError(.unsupportedURL) that a scheme-less empty URL used to produce.
    case notConnected
}

public struct ServerHistoryEntry: Codable {
    public let hash: String
    public let time: Int
    public let fullyPlayed: Bool
}

// Mirrors the server's VolumeAdjustment wire type. Only the fields relevant to
// `scope` are set: track -> sha1, album -> artist + album, artist -> artist.
public struct VolumeAdjustment: Codable, Sendable {
    public let scope: String
    public let sha1: String?
    public let artist: String?
    public let album: String?
    public let decibels: Double

    public init(scope: String, sha1: String? = nil, artist: String? = nil,
                album: String? = nil, decibels: Double) {
        self.scope = scope
        self.sha1 = sha1
        self.artist = artist
        self.album = album
        self.decibels = decibels
    }
}

// Mirrors the server's MasterVolume wire type: the single global gain (dB, <= 0).
public struct MasterVolume: Codable {
    public let decibels: Double
    public init(decibels: Double) { self.decibels = decibels }
}

// @unchecked Sendable: stored state is immutable (serverUrl / authHeaderValue are
// `let`); networking is stateless URLSession work. Subclasses (ServerAudioPlayer)
// add their own synchronization. See the client concurrency note in AsyncAudioPlayer.
public class ServerConnection: ObservableObject, ServerType, @unchecked Sendable {
    
    let serverUrl: String
    public let authHeaderValue: String

    public var url: String { return serverUrl }

    public var hasServer: Bool { return !serverUrl.isEmpty }

    // The bearer token IS the credential now (no client-side hashing). For a
    // loopback connection on the same machine as the daemon, the server trusts the
    // peer regardless of the token, so a placeholder like "local" is fine and keeps
    // the streaming path (/stream/<token>/<sha1>) well-formed.
    public init(toUrl url: String, withToken token: String) {
        self.serverUrl = url
        self.authHeaderValue = token
    }

    internal func request(path: String) async throws {
        guard hasServer else { throw ServerConnectionError.notConnected }
        guard let url = URL(string: "\(serverUrl)/\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60.0

        _ = try await URLSession.shared.data(for: request)
    }

    internal func post(body: Data, toPath path: String) async throws {
        guard hasServer else { throw ServerConnectionError.notConnected }
        guard let url = URL(string: "\(serverUrl)/\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60.0
        request.httpBody = body

        _ = try await URLSession.shared.data(for: request)
    }

    internal func requestJson<T>(atPath path: String) async throws -> T where T: Decodable {
        guard hasServer else { throw ServerConnectionError.notConnected }
        let urlPath = path.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: "\(serverUrl)/\(urlPath)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeaderValue, forHTTPHeaderField:"Authorization")
        request.timeoutInterval = 60.0

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func post(history: ServerHistoryEntry) async throws {
        let encoder = JSONEncoder()
        let jsonString = try encoder.encode(history)
        try await self.post(body: jsonString, toPath: "history")
    }

    public func listTracks() async throws -> [AudioTrack] {
        try await self.requestJson(atPath: "tracks")
    }

    // XXX no callers anywhere in the repo; kept for parity with the server's
    // /info/<hash> endpoint in case a caller shows up.
    func trackInfo(forHash hash: String) async throws -> AudioTrack {
        try await self.requestJson(atPath: "info/\(hash)")
    }

    public func listHistory() async throws -> PlayingHistory {
        try await self.requestJson(atPath: "history")
    }

    public func listHistory(since: Int) async throws -> PlayingHistory {
        try await self.requestJson(atPath: "history/\(since)")
    }

    public func setVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws {
        let body = try JSONEncoder().encode(adjustment)
        try await self.post(body: body, toPath: "volume")
    }

    public func clearVolumeAdjustment(_ adjustment: VolumeAdjustment) async throws {
        let body = try JSONEncoder().encode(adjustment)
        try await self.post(body: body, toPath: "volume/clear")
    }

    public func listVolumeAdjustments() async throws -> [VolumeAdjustment] {
        try await self.requestJson(atPath: "volume")
    }

    // The server always resolves an effective (default 0 dB) gain server-side, so
    // this never actually returns nil today; the Optional return is kept because
    // "no adjustment on record" is a meaningful, non-error outcome for callers
    // (they treat nil the same as 0 dB) -- only a failed HTTP request/decode throws.
    public func savedGain(forHash hash: String) async throws -> Double? {
        let adjustment: VolumeAdjustment = try await self.requestJson(atPath: "volume/for/\(hash)")
        return adjustment.decibels
    }

    // See savedGain(forHash:) above: the server always resolves a value (default
    // 0 dB), so this never actually returns nil today, but nil remains a valid,
    // non-error outcome for callers. Only a failed HTTP request/decode throws.
    public func masterGain() async throws -> Double? {
        let masterVolume: MasterVolume = try await self.requestJson(atPath: "volume/master")
        return masterVolume.decibels
    }

    public func setMasterGain(_ decibels: Double) async throws {
        let body = try JSONEncoder().encode(MasterVolume(decibels: decibels))
        try await self.post(body: body, toPath: "volume/master")
    }
}

