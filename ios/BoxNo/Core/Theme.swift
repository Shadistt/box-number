import SwiftUI
import UIKit

/// Палитра: светлая по макетам, тёмная — те же роли на тёмном фоне. Цвета динамические (UIColor dynamicProvider),
/// тема выбирается в Настройках (системная / светлая / тёмная) и применяется через preferredColorScheme.
enum Theme {
    static let bg = dyn(0xF1F0EC, 0x121214)
    static let ink = dyn(0x16171A, 0xF2F1EE)
    static let onInk = dyn(0xFFFFFF, 0x16171A)      // текст/иконки на заливке ink
    static let accent = Color(hex: 0xF0561D)
    static let muted = dyn(0x5E6066, 0x9EA0A7)
    static let line = dyn(0xD9D6CF, 0x33343A)
    static let card = dyn(0xFFFFFF, 0x1E1F23)
    static let fill = dyn(0xE4E2DC, 0x2A2B30)       // сегменты, вторичные кнопки
    static let tile = dyn(0xE8E6E0, 0x2A2B30)       // фон плитки места
    static let dark = Color(hex: 0x16171A)          // всегда тёмное: карточки переездов, плашка «запаковано»
    static let radius: CGFloat = 16

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Выбор темы: хранится в UserDefaults, nil = как в системе.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Как в системе"; case .light: "Светлая"; case .dark: "Тёмная" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    static let key = "app_theme"
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
    var ink: Color = Theme.onInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius))
            .foregroundStyle(ink)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
