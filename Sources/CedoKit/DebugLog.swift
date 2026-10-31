import Foundation
import Observation

@MainActor
@Observable
public final class DebugLog {
    public struct Entry: Identifiable, Sendable {
        public let id: Int
        public let date: Date
        public let message: String
        public let isError: Bool
    }

    private static let limit = 1000

    public private(set) var entries: [Entry] = []
    @ObservationIgnored private var nextID = 0

    public nonisolated init() {}

    public nonisolated func info(_ message: String) {
        add(message, isError: false)
    }

    public nonisolated func error(_ message: String) {
        add(message, isError: true)
    }

    private nonisolated func add(_ message: String, isError: Bool) {
        let date = Date()
        NSLog("cedo: %@", message)
        // Synchronous on the main thread, so entries stay in the order they were logged
        if Thread.isMainThread {
            MainActor.assumeIsolated { append(message, date: date, isError: isError) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.append(message, date: date, isError: isError) } }
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
