import SwiftUI

/// Тема: как в системе / светлая / тёмная — три карточки-превью (паттерн Binance / Ubank «Appearance» с Mobbin).
struct ThemeView: View {
    @AppStorage(AppTheme.key) private var theme: String = AppTheme.light.rawValue   // по умолчанию светлая, пока тёмную не отсмотрели

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Тёмная тема бережёт глаза вечером; «Как в системе» переключается вместе с iPhone.")
                    .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { t in
                        let on = theme == t.rawValue
                        Button { withAnimation(.snappy) { theme = t.rawValue } } label: {
                            VStack(spacing: 10) {
                                preview(t)
                                Text(t.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                                    .foregroundStyle(on ? Theme.accent : Theme.line)
                            }
                            .padding(10).frame(maxWidth: .infinity)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Тема").navigationBarTitleDisplayMode(.inline)
    }

    /// Мини-экран: фон + две «карточки»; «как в системе» — половина светлая, половина тёмная.
    private func preview(_ t: AppTheme) -> some View {
        let light = (bg: Color(hex: 0xF1F0EC), card: Color.white, ink: Color(hex: 0x16171A))
        let dark = (bg: Color(hex: 0x121214), card: Color(hex: 0x1E1F23), ink: Color(hex: 0xF2F1EE))
        func half(_ c: (bg: Color, card: Color, ink: Color)) -> some View {
            ZStack(alignment: .top) {
                c.bg
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(c.ink.opacity(0.8)).frame(width: 28, height: 6).padding(.top, 10)
                    RoundedRectangle(cornerRadius: 5).fill(c.card).frame(height: 22).padding(.horizontal, 8)
                    RoundedRectangle(cornerRadius: 5).fill(c.ink).frame(height: 22).padding(.horizontal, 8)
                }
            }
        }
        return ZStack {
            switch t {
            case .light: half(light)
            case .dark: half(dark)
            case .system: HStack(spacing: 0) { half(light); half(dark) }
            }
        }
        .frame(height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
