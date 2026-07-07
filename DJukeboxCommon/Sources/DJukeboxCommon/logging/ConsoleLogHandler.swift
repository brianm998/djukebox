import Foundation

// @unchecked: the non-Sendable DateFormatter is only ever touched inside the
// private serial `dispatchQueue`, so the class synchronizes its own state.
public final class ConsoleLogHandler: LogHandler, @unchecked Sendable {

    public let dispatchQueue: DispatchQueue
    public let level: Log.Level?
    private let dateFormatter = DateFormatter()

    public init(at level: Log.Level) {
        self.level = level
        dateFormatter.dateFormat = "H:mm:ss.SSSS"
        self.dispatchQueue = DispatchQueue(label: "fileLogging")
    }
    
    public func log(message: String,
                    at fileLocation: String,
                    with data: LogData?,
                    at logLevel: Log.Level)
    {
        dispatchQueue.async {
            let dateString = self.dateFormatter.string(from: Date())
            
            if let data {
                print("\(dateString) | \(logLevel.emo) \(logLevel) | \(fileLocation): \(message) | \(data.description)")
            } else {
                print("\(dateString) | \(logLevel.emo) \(logLevel) | \(fileLocation): \(message)")
            }
        }
    }
}

