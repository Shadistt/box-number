import SwiftUI
import StoreKit

/// Документы, конфиденциальность и поддержка (макет Docs).
struct DocsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SectionTitle("Документы")
                SettingsCard {
                    linkRow("Условия использования", "https://boxnumber.co/terms")
                    Divider().padding(.leading, 16)
                    linkRow("Политика конфиденциальности", "https://boxnumber.co/privacy")
                    Divider().padding(.leading, 16)
                    NavigationLink { LicensesView() } label: { Row("Лицензии открытого ПО") }
                }
                SectionTitle("Помощь")
                SettingsCard {
                    NavigationLink { SupportView() } label: { Row("Написать в поддержку") }
                    Divider().padding(.leading, 16)
                    linkRow("Частые вопросы", "https://boxnumber.co/faq")
                    Divider().padding(.leading, 16)
                    Button { requestReview() } label: { Row("Оценить в App Store", chevron: false) }
                }
                VStack(spacing: 4) {
                    (Text("Box ") + Text("Nº").foregroundStyle(Theme.accent)).font(.system(size: 22, weight: .heavy))
                    Text("Версия \(version) · boxnumber.co").font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.top, 24)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Документы и поддержка").navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ title: String, _ url: String) -> some View {
        Button { openURL(URL(string: url)!) } label: { Row(title) }
    }
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct LicensesView: View {
    private let items: [(String, String, String)] = [
        ("supabase-swift", "MIT", "https://github.com/supabase/supabase-swift"),
        ("GoogleSignIn-iOS", "Apache-2.0", "https://github.com/google/GoogleSignIn-iOS"),
        ("Permanent Marker (шрифт)", "Apache-2.0", "https://fonts.google.com/specimen/Permanent+Marker"),
        ("SigLIP 2 (модель распознавания)", "Apache-2.0", "https://huggingface.co/google/siglip2-base-patch16-224"),
    ]
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            SettingsCard {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { Divider().padding(.leading, 16) }
                    Button { openURL(URL(string: it.2)!) } label: { Row(it.0, value: it.1) }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Лицензии").navigationBarTitleDisplayMode(.inline)
    }
}
