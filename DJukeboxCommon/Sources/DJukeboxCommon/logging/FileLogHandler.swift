
import Foundation

// @unchecked: the non-Sendable DateFormatter and log file are only ever touched
// inside the private serial `dispatchQueue`, so the class synchronizes its own state.
public final class FileLogHandler: LogHandler, @unchecked Sendable {

    let dateFormatter = DateFormatter()
    public let dispatchQueue: DispatchQueue
    public let level: Log.Level?
    private let logfilename: String

    public init(at level: Log.Level) {
        self.level = level
        // this is for the logfile name
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        self.logfilename = "log-\(dateString).txt"
        self.dispatchQueue = DispatchQueue(label: "consoleLogging")

        // this is for log lines
        dateFormatter.dateFormat = "H:mm:ss.SSSS"
    }
    
    public func log(message: String,
                    at fileLocation: String,
                    with data: LogData?,
                    at logLevel: Log.Level)
    {
        dispatchQueue.async {
            let dateString = self.dateFormatter.string(from: Date())
            
            if let data {
                self.writeToLogFile("\(dateString) | \(logLevel) | \(fileLocation): \(message) | \(data.description)\n")
            } else {
                self.writeToLogFile("\(dateString) | \(logLevel) | \(fileLocation): \(message)\n")
            }
        }
    }

    private func writeToLogFile(_ message: String) {
        guard let messageData = message.data(using: .utf8) else { return }
        if let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {

            let logURL = documentDirectory.appendingPathComponent(logfilename)
            if FileManager.default.fileExists(atPath: logURL.path) {
                guard let fileHandle = try? FileHandle.init(forWritingTo: logURL) else { return }
                do {
                    try fileHandle.seekToEnd()
                    try fileHandle.write(contentsOf: messageData)
                    try fileHandle.close()
                } catch {
                    // best-effort logging; nowhere to report a write failure from here
                }
            } else {
                FileManager.default.createFile(atPath: logURL.path, contents: messageData, attributes: nil)
            }
        }
    }
}
