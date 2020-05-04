import Foundation

public protocol HistoryWriterType {
    func writePlay(of sha1: String, at date: Date) throws
    func writeSkip(of sha1: String, at date: Date) throws
}

