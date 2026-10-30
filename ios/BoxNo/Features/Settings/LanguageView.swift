import SwiftUI

/// Язык интерфейса и новых AI-подписей (макет Language). Сохраняется в profiles.locale.
/// Сам интерфейс пока только русский; значение влияет на подписи вещей, когда появятся другие языки.
struct Language: Identifiable, Hashable {
    let id: String       // в profiles.locale; "system" = как в системе
    let native: String
    let local: String

    static let all: [Language] = [
        .init(id: "system", native: "Как в системе", local: systemLanguageName),
        .init(id: "ru", native: "Русский", local: ""),
        .init(id: "uk", native: "Українська", local: "Украинский"),
        .init(id: "en", native: "English", local: "Английский"),
        .init(id: "de", native: "Deutsch", local: "Немецкий"),
        .init(id: "fr", native: "Français", local: "Французский"),
        .init(id: "es", native: "Español", local: "Испанский"),
        .init(id: "it", native: "Italiano", local: "Итальянский"),
        .init(id: "nl", native: "Nederlands", local: "Нидерландский"),
        .init(id: "pl", native: "Polski", local: "Польский"),
        .init(id: "pt", native: "Português", local: "Португальский"),
    ]
    static func current(_ locale: String?) -> Language { all.first { $0.id == locale } ?? all[1] }

    /// Язык системы по-русски («Английский»), чтобы «Как в системе» не врал.
    static var systemLanguageName: String {
        // Без обращения к `all`: оно само строится из этого значения.
        let code = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "ru"
        return Locale(identifier: "ru").localizedString(forLanguageCode: code)?.capitalized ?? code
    }
}

struct LanguageView: View {
    @State private var store = ProfileStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Язык интерфейса и новых AI-подписей.").font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                SettingsCard {
                    ForEach(Array(Language.all.enumerated()), id: \.element.id) { i, l in
                        if i > 0 { Divider().padding(.leading, 16) }
                        let on = Language.current(store.profile?.locale).id == l.id
                        Button { Task { await store.update(locale: l.id) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.native).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                                    if !l.local.isEmpty { Text(l.local).font(.footnote).foregroundStyle(Theme.muted) }
                                }
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent) }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
                        }
                    }
                }
                Text("Новые AI-подписи будут на выбранном языке. Уже сделанные подписи останутся как есть.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Язык").navigationBarTitleDisplayMode(.inline)
    }
}
