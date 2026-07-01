
import Foundation

public protocol LogHandler: Sendable {
    func log(message: String,
             at fileLocation: String,
             with data: LogData?,
             at logLevel: Log.Level)

    var dispatchQueue: DispatchQueue { get }
    // read-only: handlers set their level once, at init (the setter was never used)
    var level: Log.Level? { get }
}

