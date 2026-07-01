import Foundation

// @unchecked: immutable value holder; `encodable` is a non-Sendable existential
// but is always nil here and never mutated.
public struct StringLogData: LogData, @unchecked Sendable {

    public let encodable: Encodable? = nil
    public let description: String

    public init(with convertable: CustomStringConvertible) {
        self.description = convertable.description
    }

    public init(with string: String) {
        self.description = string
    }

    public init<T>(with data: T) {
        self.description = String(describing: data)
    }
}

