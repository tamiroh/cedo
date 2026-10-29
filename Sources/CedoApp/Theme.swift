import SwiftUI

enum Theme {
    static let background = Color(hex: 0x181818)
    static let inset = Color(hex: 0x141414)
    static let surface = Color(hex: 0x262626)
    static let selected = Color(hex: 0x2e2e2e)
    static let border = Color(hex: 0x404040)
    static let text = Color(hex: 0xe2e2e2)
    static let muted = Color(hex: 0x999999)
    static let selection = Color(hex: 0x34425a)
    static let danger = Color(hex: 0xf0776c)
    static let added = Color(hex: 0xa8c98a)
    static let removed = danger
    static let hunk = Color(hex: 0x8cb4f0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
