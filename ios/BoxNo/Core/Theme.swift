import SwiftUI

enum Theme {
    static let bg = Color(hex: 0xF1F0EC)
    static let ink = Color(hex: 0x16171A)
    static let accent = Color(hex: 0xF0561D)
    static let muted = Color(hex: 0x5E6066)
    static let line = Color(hex: 0xD9D6CF)
    static let card = Color.white
    static let radius: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.ink
    var ink: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius))
            .foregroundStyle(ink)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
