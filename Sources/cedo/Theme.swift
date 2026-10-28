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

/// A transparent button with a thin border that fills in on hover.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OutlineButton(configuration: configuration)
    }

    private struct OutlineButton: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovering || configuration.isPressed ? Theme.surface : .clear)
                )
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
