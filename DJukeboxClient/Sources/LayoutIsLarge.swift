import Foundation

// do we have a big, or a small screen?
public func layoutIsLarge() -> Bool {
    #if os(iOS)// || os(watchOS) || os(tvOS)
    if UIDevice.current.userInterfaceIdiom == .pad {
        return true
    }else{
        return false
    }
    #elseif os(OSX)
    return true
    #else
    return false
    #endif
}

// XXX move these
public func string(forTime date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .none
    dateFormatter.timeStyle = .medium
    return dateFormatter.string(from: date)
}

public func format(duration: TimeInterval) -> String {
    let seconds = Int(duration) % 60
    let minutes = Int(duration/60) % 60
    let hours = Int(duration/(60*60))
    if hours > 0 {
        return "\(hours) hours"
    } else if minutes > 0 {
        return "\(minutes) minutes"
    } else {
        return "\(seconds) seconds"
    }
}

