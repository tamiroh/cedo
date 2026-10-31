import Foundation
import Observation

@Observable
public final class DebugLog {
    public struct Entry: Identifiable {
        public let id: Int
        public let date: Date
        public let message: String
        public let isError: Bool
    }

    private static let limit = 1000

    /// Updated on the main thread only.
    public private(set) var entries: [Entry] = []
    @ObservationIgnored private var nextID = 0

    public init() {}

    public func info(_ message: String) {
        add(message, isError: false)
    }

    public func error(_ message: String) {
        add(message, isError: true)
    }

    private func add(_ message: String, isError: Bool) {
        let date = Date()
        NSLog("cedo: %@", message)
        if Thread.isMainThread {
            append(message, date: date, isError: isError)
        } else {
            DispatchQueue.main.async { self.append(message, date: date, isError: isError) }
        }
    }

    private func append(_ message: String, date: Date, isError: Bool) {
        entries.append(Entry(id: nextID, date: date, message: message, isError: isError))
        nextID += 1
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }
}
