import Foundation

extension String {
    /// Replaces invalid bytes with U+FFFD.
    /// Only for text that is read, never written back, such as the output of tools.
    init(lossyUTF8 data: Data) {
        self.init(decoding: data, as: UTF8.self)
    }
}
