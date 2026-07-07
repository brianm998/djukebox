
import Foundation

// @unchecked: the non-Sendable DateFormatter and log file are only ever touched
// inside the private serial `dispatchQueue`, so the class synchronizes its own state.
public final class FileLogHandler: LogHandler, @unchecked Sendable {

    // for log lines (H:mm:ss.SSSS); kept as DateFormatter since Date.FormatStyle
    // has no direct equivalent for fixed 4-digit fractional seconds.
    let dateFormatter = DateFormatter()
    public let dispatchQueue: DispatchQueue
    public let level: Log.Level?
    private let logfilename: String

    // A fixed, non-localized "yyyy-MM-dd-HH-mm-ss" stamp for the filename, built
    // with the value-type (Sendable) VerbatimFormatStyle instead of a DateFormatter.
    private static let filenameFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))-\(minute: .twoDigits)-\(second: .twoDigits)",
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian))

    public init(at level: Log.Level) {
        self.level = level
        // this is for the logfile name
        let dateString = Date().formatted(FileLogHandler.filenameFormat)
        self.logfilename = "log-\(dateString).txt"
        self.dispatchQueue = DispatchQueue(label: "fileLogging")

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
