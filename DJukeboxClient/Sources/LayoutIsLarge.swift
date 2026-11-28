import Foundation
#if os(iOS)
import UIKit
#endif

// do we have a big, or a small screen?
@MainActor
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
    date.formatted(date: .omitted, time: .standard)
}

public func format(duration: TimeInterval) -> String {
    // nil for NaN, infinity and anything too large for an Int, which Int() traps on
    guard let total = Int(exactly: duration.rounded(.towardZero)) else { return "" }
    let seconds = total % 60
    let minutes = (total / 60) % 60
    let hours = total / (60*60)
    if hours > 0 {
        return "\(hours) hours"
    } else if minutes > 0 {
        return "\(minutes) minutes"
    } else {
        return "\(seconds) seconds"
    }
}

