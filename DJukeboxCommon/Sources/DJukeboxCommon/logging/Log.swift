
import Foundation

/*

 Debug Log functions:

   Log.debug()
   Log.debug("something happened")
   Log.debug("something happened", somedata)
   Log.debug(somedata)
   Log.debug("something happened", [somedata, otherdata])
   Log.debug([somedata, otherdata])

   or 

   Log.d()
   Log.d("something happened")
   Log.d("something happened", somedata)
   Log.d(somedata)
   Log.d("something happened", [somedata, otherdata])
   Log.d([somedata, otherdata])

 Info Log functions:

   Log.info()
   Log.info("something happened")
   Log.info("something happened", somedata)
   Log.info(somedata)
   Log.info("something happened", [somedata, otherdata])
   Log.info([somedata, otherdata])

   or 

   Log.i()
   Log.i("something happened")
   Log.i("something happened", somedata)
   Log.i(somedata)
   Log.i("something happened", [somedata, otherdata])
   Log.i([somedata, otherdata])

 Warn Log functions:

   Log.warn()
   Log.warn("something happened")
   Log.warn("something happened", somedata)
   Log.warn(somedata)
   Log.warn("something happened", [somedata, otherdata])
   Log.warn([somedata, otherdata])

   or 

   Log.w()
   Log.w("something happened")
   Log.w("something happened", somedata)
   Log.w(somedata)
   Log.w("something happened", [somedata, otherdata])
   Log.w([somedata, otherdata])

 Error Log functions:

   Log.error()
   Log.error("something happened")
   Log.error("something happened", somedata)
   Log.error(somedata)
   Log.error("something happened", [somedata, otherdata])
   Log.error([somedata, otherdata])
   Log.error(error) // can be any Error

   or 

   Log.e()
   Log.e("something happened")
   Log.e("something happened", somedata)
   Log.e(somedata)
   Log.e("something happened", [somedata, otherdata])
   Log.e([somedata, otherdata])
   Log.e(error) // can be any Error


 When called with no arguments, the above functions will simply record that an event
 of some type (debug, info, warn, error) occured at a specific time, in a particular file,
 function, and line number.

 While not required, arguments can be given in the format of a string, and/or some data.  

 In all cases, 'some data' is handled generically.

 If somedata is Encodable, handlers will be passed a LogData as such.
 Encodable log data will represent this data as json via the string description property.
 If somedata is CustomStringConvertible the description property will be used.
 Otherwise a string describing it will be used by handlers.

*/

public class Log {

    /*
        Handlers can be set during app startup in the app delegate as follows:

        Log.handlers = 
          [
            .console: ConsoleLogHandler(at: .info),
            .file   : FileLogHandler(at: .debug),
          ]

        If handlers are not set elsewhere, the following will then apply:
     */
    // nonisolated(unsafe): handlers are configured once at app/server startup
    // (before any logging happens) and only read afterwards.
    nonisolated(unsafe) public static var handlers: [Log.Output: LogHandler] =
      [
        .console: ConsoleLogHandler(at: .debug),
      ]

    public enum Output: Sendable {
        case console
        case file
        case alert
    }

    public enum Level: String, CustomStringConvertible, CaseIterable, Sendable {
        case debug
        case info
        case warn
        case error
        
        public static func <=(_ left: Level, right: Level) -> Bool {
            return left.num <= right.num
        }

        public var emo: String {
            switch self {
            case .debug:
                return "👩‍💻"
            case .info:
                return "ℹ️"
            case .warn:
                return "⚠️"
            case .error:
                return "☠️"
            }
        }

        public var description: String {
            switch self {
            case .debug:
                return "DEBUG"
            case .info:
                return "INFO"
            case .warn:
                return "WARN"
            case .error:
                return "ERROR"
            }
        }

        private var num: Int {
            switch self {
            case .debug:
                return 3
            case .info:
                return 2
            case .warn:
                return 1
            case .error:
                return 0
            }
        }
    }
}

extension Log {                 
    /*
       Log.debug()
       Log.debug("something happened")
     */
    public static func debug(_ message: String? = nil,
                             file: String = #file,
                             function: String = #function,
                             line: Int = #line)
    {
        logInternal(message, at: Level.debug, file, function, line)
    }

    /*
       Log.debug("something happened", somedata)
     */
    public static func debug<T>(_ message: String? = nil,
                                _ data: T?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line) 
    {
        logInternal(message, with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.debug(somedata)
     */
    public static func debug<T>(_ data: T?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.debug("something happened", [somedata, otherdata])
     */
    public static func debug<T>(_ message: String? = nil,
                                _ data: [T]?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(message, with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.debug([somedata, otherdata])
     */
    public static func debug<T>(_ data: [T]?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(with: data, at: .debug, file, function, line)
    }
}

extension Log {                 
    /*
       Log.d()
       Log.d("something happened")
     */
    public static func d(_ message: String? = nil,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line)
    {
        logInternal(message, at: Level.debug, file, function, line)
    }

    /*
     Log.d("something happened", somedata)
     */
    public static func d<T>(_ message: String? = nil,
                            _ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line) 
    {
        logInternal(message, with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.d(somedata)
     */
    public static func d<T>(_ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.d("something happened", [somedata, otherdata])
     */
    public static func d<T>(_ message: String? = nil,
                            _ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .debug, file, function, line)
    }
    
    /*
       Log.d([somedata, otherdata])
     */
    public static func d<T>(_ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .debug, file, function, line)
    }
}

extension Log {                 // info
    /*
       Log.info()
       Log.info("something happened")
     */
    public static func info(_ message: String? = nil,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, at: .info, file, function, line)
    }

    /*
       Log.info("something happened", somedata)
     */
    public static func info<T>(_ message: String? = nil,
                               _ data: T?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(message, with: data, at: .info, file, function, line)
    }

    /*
       Log.info(somedata)
     */
    public static func info<T>(_ data: T?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(with: data, at: .info, file, function, line)
    }

    /*
       Log.info("something happened", [somedata, otherdata])
     */
    public static func info<T>(_ message: String? = nil,
                               _ data: [T]?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(message, with: data, at: .info, file, function, line)
    }

    /*
       Log.info([somedata, otherdata])
     */
    public static func info<T>(_ data: [T]?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(with: data, at: .info, file, function, line)
    }
}

extension Log {                 // i
    /*
       Log.i()
       Log.i("something happened")
     */
    public static func i(_ message: String? = nil,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line)
    {
        logInternal(message, at: .info, file, function, line)
    }

    /*
       Log.i("something happened", somedata)
     */
    public static func i<T>(_ message: String? = nil,
                               _ data: T?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(message, with: data, at: .info, file, function, line)
    }

    /*
       Log.i(somedata)
     */
    public static func i<T>(_ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .info, file, function, line)
    }

    /*
       Log.i("something happened", [somedata, otherdata])
     */
    public static func i<T>(_ message: String? = nil,
                            _ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .info, file, function, line)
    }

    /*
       Log.i([somedata, otherdata])
     */
    public static func i<T>(_ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .info, file, function, line)
    }
}

extension Log {
    /*
       Log.warn()
       Log.warn("something happened")
     */
    public static func warn(_ message: String? = nil,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, at: .warn, file, function, line)
    }

    /*
       Log.warn("something happened", somedata)
     */
    public static func warn<T>(_ message: String? = nil,
                               _ data: T?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(message, with: data, at: .warn, file, function, line)
    }

    /*
       Log.warn(somedata)
     */
    public static func warn<T>(_ data: T?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(with: data, at: .warn, file, function, line)
    }

    /*
       Log.warn("something happened", [somedata, otherdata])
     */
    public static func warn<T>(_ message: String? = nil,
                               _ data: [T]?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(message, with: data, at: .warn, file, function, line)
    }

    /*
       Log.warn([somedata, otherdata])
     */
    public static func warn<T>(_ data: [T]?,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line)
    {
        logInternal(with: data, at: .warn, file, function, line)
    }
}

extension Log {
    /*
       Log.w()
       Log.w("something happened")
     */
    public static func w(_ message: String? = nil,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line)
    {
        logInternal(message, at: .warn, file, function, line)
    }

    /*
       Log.w("something happened", somedata)
     */
    public static func w<T>(_ message: String? = nil,
                            _ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .warn, file, function, line)
    }

    /*
       Log.w(somedata)
     */
    public static func w<T>(_ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .warn, file, function, line)
    }

    /*
       Log.w("something happened", [somedata, otherdata])
     */
    public static func w<T>(_ message: String? = nil,
                            _ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .warn, file, function, line)
    }

    /*
       Log.w([somedata, otherdata])
     */
    public static func w<T>(_ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .warn, file, function, line)
    }
}

extension Log {
    /*
       Log.error()
       Log.error("something happened")
     */
    public static func error(_ message: String? = nil,
                             file: String = #file,
                             function: String = #function,
                             line: Int = #line)
    {
        logInternal(message,
                    at: .error,
                    file, function, line)
    }

    /*
       Log.error(error)
     */
    public static func error(_ error: Error? = nil,
                             file: String = #file,
                             function: String = #function,
                             line: Int = #line)
    {
        logInternal(at: .error, file, function, line)
    }

    /*
       Log.error(somedata)
       Log.error("something happened", somedata)
     */
    public static func error<T>(_ message: String? = nil,
                                _ data: T?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(message, with: data, at: .error, file, function, line)
    }

    /*
       Log.error("something happened", [somedata, otherdata])
     */
    public static func error<T>(_ data: T?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(with: data, at: .error, file, function, line)
    }

    /*
       Log.error([somedata, otherdata])
     */
    public static func error<T>(_ message: String? = nil,
                                _ data: [T]?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(message, with: data, at: .error, file, function, line)
    }

    /*
       Log.error([somedata, otherdata])
     */
    public static func error<T>(_ data: [T]?,
                                file: String = #file,
                                function: String = #function,
                                line: Int = #line)
    {
        logInternal(with: data, at: .error, file, function, line)
    }

}

extension Log {
    /*
       Log.e()
       Log.e("something happened")
     */
    public static func e(_ message: String? = nil,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line)
    {
        logInternal(message,
                    at: .error,
                    file, function, line)
    }

    /*
       Log.error(error)
     */
    public static func e(_ error: Error? = nil,
                         file: String = #file,
                         function: String = #function,
                         line: Int = #line)
    {
        logInternal(at: .error, file, function, line)
    }

    /*
       Log.e(somedata)
       Log.e("something happened", somedata)
     */
    public static func e<T>(_ message: String? = nil,
                            _ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .error, file, function, line)
    }

    /*
       Log.e("something happened", [somedata, otherdata])
     */
    public static func e<T>(_ data: T?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .error, file, function, line)
    }

    /*
       Log.e([somedata, otherdata])
     */
    public static func e<T>(_ message: String? = nil,
                            _ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(message, with: data, at: .error, file, function, line)
    }

    /*
       Log.e([somedata, otherdata])
     */
    public static func e<T>(_ data: [T]?,
                            file: String = #file,
                            function: String = #function,
                            line: Int = #line)
    {
        logInternal(with: data, at: .error, file, function, line)
    }

}

// after here are the internal implemenation details

// (Previously a fileprivate `backgroundTask` global lived here, but it was only
// ever referenced by the commented-out code in logInternal below. Under Swift 6
// it is not concurrency-safe — BackgroundTask is non-Sendable and .start() is
// @MainActor — so the dead global has been removed.)

fileprivate extension Log {
    
    static func logInternal(_ message: String? = nil,
                            at logLevel: Level,
                            _ file: String,
                            _ function: String,
                            _ line: Int)
    {
        logInternal(message, with: Optional<Int>.none, at: logLevel, file, function, line)
    }
    
    static func logInternal<T>(_ message: String? = nil,
                               with data: T? = Optional<T>.none,
                               at logLevel: Level,
                               _ file: String,
                               _ function: String,
                               _ line: Int)
    {
        // Build everything the handlers need here on the calling thread, so that
        // only Sendable values (String / LogData / Level) are captured by the
        // @Sendable closure handed to the logging queue. (The generic, possibly
        // non-Sendable `data` never crosses the concurrency boundary.)
        let string: String
        if let message {
            string = message
        } else if data != nil {
            string = logLevel.description
        } else {
            string = ""
        }

        let fileLocation = "\(parseFileName(file)).\(function)@\(line)"

        let extraData: LogData?
        if let data {
            if let encodableData = data as? Encodable,
               let encodableLogData = EncodableLogData(with: encodableData)
            {
                // first we try to json encode any Encodable data
                extraData = encodableLogData
            } else if let stringConvertibleData = data as? CustomStringConvertible {
                // then we try the description of any CustomStringConvertible data
                extraData = StringLogData(with: stringConvertibleData)
            } else {
                // our final fallback for data we don't have a better way to encode
                extraData = StringLogData(with: data)
            }
        } else {
            extraData = nil
        }

        logQueue.async {
            for handler in handlers.values {
                if let handlerLevel = handler.level,
                   logLevel <= handlerLevel
                {
                    handler.log(message: string,
                                at: fileLocation,
                                with: extraData,
                                at: logLevel)
                }
            }
        }
    }
    
    static func parseFileName(_ file: String) -> String {
        let filename = file.components(separatedBy: "/").last ?? file
        return filename.components(separatedBy: ".").first ?? filename
    }
}


// Deliberately still a serial DispatchQueue, not an actor: a DispatchQueue
// guarantees strict FIFO ordering of enqueued blocks, which an actor's task
// scheduling does not — swapping this (or the per-handler queues below) for
// actors risks reordering log lines under concurrent logging, which matters
// for a logging system. dispatchQueue is also a public LogHandler requirement
// LOG_ABORT() relies on to sequence its abort after pending prints. See
// docs/modernization-audit.md F47 for the fuller writeup of this decision.
fileprivate let logQueue = DispatchQueue(label: "logging")
#if !os(macOS)
//fileprivate var backgroundTask: BackgroundTask?
#endif

// after here is all testing code

#if DEBUG
// this is helpful when testing logging, to see a few test lines, and then avoid further spew 
public func LOG_ABORT() {
    logQueue.async {
        Log.handlers[.console]?.dispatchQueue.async {
            print("\n\n")
            print("☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️")
            print("☠️☠️☠️ was asked to abort ☠️☠️☠️")
            print("☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️☠️")
            print("\n\n")
            abort()
        }
    }
}

fileprivate struct LogTest: Codable {
    let foo: String
    let bar: Int?
}
    
#else
public func LOG_ABORT() {}
#endif

