import Foundation

public extension Encodable {
    var jsonData: Data? { return try? JSONEncoder().encode(self) }
}

public extension Data {
    var utf8String: String? { return String(data: self, encoding: .utf8) }
}

// @unchecked: immutable value holder; the stored `any Encodable` is not itself
// Sendable, but it is a `let` set once at init and only used for read-only logging.
public struct EncodableLogData: LogData, @unchecked Sendable {

    public let encodable: Encodable?
    public let description: String

    public init?(with encodable: Encodable) {
        if let description = encodable.jsonData?.utf8String {
            self.description = description
        } else {
            return nil
        }
        self.encodable = encodable
    }
}

