import Foundation

public struct Document: Equatable {
    public enum SaveResult: Equatable {
        case saved
        case unchanged
        case conflict(onDisk: String)
        /// The file was deleted or can no longer be read as UTF-8, so saving would replace what cedo never saw.
        case unreadable
    }

    public enum OutsideChange: Equatable {
        case unchanged
        case reloaded
        case conflict(onDisk: String)
    }

    public let url: URL
    public var text: String
    private var savedText: String
    private var savedModificationDate: Date?

    public var isDirty: Bool { text != savedText }

    public init?(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.url = url
        text = content
        savedText = content
        savedModificationDate = Self.modificationDate(of: url)
    }

    public mutating func save(overwritingOutsideChanges: Bool = false) throws -> SaveResult {
        guard isDirty else { return .unchanged }
        if !overwritingOutsideChanges {
            guard let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return .unreadable }
            if onDisk != savedText {
                return .conflict(onDisk: onDisk)
            }
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        savedText = text
        savedModificationDate = Self.modificationDate(of: url)
        return .saved
    }

    public mutating func checkForOutsideChanges() -> OutsideChange {
        let date = Self.modificationDate(of: url)
        guard date != savedModificationDate,
            let onDisk = try? String(contentsOf: url, encoding: .utf8)
        else { return .unchanged }
        guard onDisk != savedText else {
            savedModificationDate = date
            return .unchanged
        }
        if isDirty {
            return .conflict(onDisk: onDisk)
        }
        adopt(onDisk)
        return .reloaded
    }

    public mutating func adopt(_ content: String) {
        text = content
        savedText = content
        savedModificationDate = Self.modificationDate(of: url)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
