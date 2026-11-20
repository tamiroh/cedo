import Foundation

public struct Document: Equatable {
    public enum SaveResult: Equatable {
        case saved
        case unchanged
        case conflict(onDisk: String)
        /// The file was deleted or can no longer be read as UTF-8, so saving would replace what Cedo never saw.
        case unreadable
    }

    public enum OutsideChange: Equatable {
        case unchanged
        case reloaded
        case conflict(onDisk: String)
    }

    public let url: URL
    public var text: String {
        didSet { lastEditedAt = .now }
    }
    public private(set) var lastEditedAt: Date
    private var savedText: String
    private var savedModificationDate: Date?
    private var hasByteOrderMark: Bool
    /// Where the text is read and written, so saving through a symbolic link keeps the link.
    private let target: URL

    // Compared byte for byte: String's == treats "é" and "e" + a combining accent as equal
    public var isDirty: Bool { !Self.same(text, savedText) }

    public init?(url: URL) {
        let target = url.resolvingSymlinksInPath()
        guard let (content, hasByteOrderMark) = Self.read(target) else { return nil }
        self.url = url
        self.target = target
        self.hasByteOrderMark = hasByteOrderMark
        text = content
        savedText = content
        savedModificationDate = Self.modificationDate(of: target)
        lastEditedAt = savedModificationDate ?? .now
    }

    public mutating func save(overwritingOutsideChanges: Bool = false) throws -> SaveResult {
        guard isDirty else { return .unchanged }
        if !overwritingOutsideChanges {
            guard let (onDisk, _) = Self.read(target) else { return .unreadable }
            if !Self.same(onDisk, savedText) {
                return .conflict(onDisk: onDisk)
            }
        }
        let bytes = Data(text.utf8)
        try ((hasByteOrderMark ? Self.byteOrderMark : Data()) + bytes).write(to: target, options: .atomic)
        savedText = text
        savedModificationDate = Self.modificationDate(of: target)
        return .saved
    }

    public mutating func checkForOutsideChanges() -> OutsideChange {
        let date = Self.modificationDate(of: target)
        guard date != savedModificationDate, let (onDisk, hasByteOrderMark) = Self.read(target) else {
            return .unchanged
        }
        guard !Self.same(onDisk, savedText) else {
            savedModificationDate = date
            return .unchanged
        }
        if isDirty {
            return .conflict(onDisk: onDisk)
        }
        self.hasByteOrderMark = hasByteOrderMark
        adopt(onDisk)
        return .reloaded
    }

    public mutating func adopt(_ content: String) {
        text = content
        savedText = content
        savedModificationDate = Self.modificationDate(of: target)
        lastEditedAt = savedModificationDate ?? .now
    }

    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    private static func read(_ url: URL) -> (String, hasByteOrderMark: Bool)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let hasByteOrderMark = data.starts(with: byteOrderMark)
        guard let text = String(data: data.dropFirst(hasByteOrderMark ? 3 : 0), encoding: .utf8) else { return nil }
        return (text, hasByteOrderMark)
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
