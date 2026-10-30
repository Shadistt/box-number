import SwiftUI

/// Настройки (макет Profile.dc.html). Карточка тарифа не делается — раздел переосмысливается (ТЗ §10).
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProfileStore.shared
    @State private var showDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Аккаунт
                    NavigationLink { AccountView() } label: {
                        SettingsCard {
                            HStack(spacing: 14) {
                                AvatarView(profile: store.profile, image: store.avatarImage, size: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.profile?.fullName.isEmpty == false ? store.profile!.fullName : "Без имени")
                                        .font(.system(size: 19, weight: .bold))
                                    Text(store.profile?.email ?? "").font(.subheadline).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(16)
                        }
                    }
                    .buttonStyle(.plain)

                    /*
                     // Тариф — не делаем до нового решения (30.10.2026). Макет: «12 мест · 2 090 фото · Pro»,
                     // бегунки Места / Фото, кнопка «Изменить» → экран «Места и фото».
                     PlanCard(usage: store.usage)
                     */
                    SettingsCard {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud").font(.system(size: 15, weight: .semibold))
                            Text(syncText).font(.footnote)
                        }
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }

                    SectionTitle("Настройки")
                    SettingsCard {
                        NavigationLink { FamilyPlaceholderView() } label: { Row("Моя семья", value: "скоро") }
                        Divider().padding(.leading, 16)
                        NavigationLink { LanguageView() } label: { Row("Язык", value: Language.current(store.profile?.locale).native) }
                    }
                    SettingsCard {
                        NavigationLink { DocsView() } label: { Row("Документы, конфиденциальность и поддержка") }
                    }
                    SettingsCard {
                        Button { confirmSignOut = true } label: { Row("Выйти", chevron: false) }
                        Divider().padding(.leading, 16)
                        Button { showDelete = true } label: { Row("Удалить аккаунт", chevron: false, color: .red) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Системная кнопка — тогда она того же размера и формы, что «назад» на вложенных экранах.
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                }
            }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await session.signOut(); dismiss() } }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Места и фото останутся в облаке — войдёте снова и всё будет на месте.") }
            .navigationDestination(isPresented: $showDelete) { DeleteAccountView() }
            .task { await store.load() }
            .refreshable { await store.load() }
        }
        .tint(Theme.ink)
    }

    private var syncText: String {
        guard let at = store.usage?.syncedAt else { return "Всё сохранено в облаке" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.doesRelativeDateFormatting = true
        f.dateStyle = .short; f.timeStyle = .short
        return "Всё сохранено в облаке · \(f.string(from: at).lowercased())"
    }
}

// MARK: - Общие элементы настроек

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Theme.muted).kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 8)
    }
}

/// Строка списка: заголовок · значение справа · шеврон.
struct Row: View {
    let title: String
    var value: String? = nil
    var chevron = true
    var color: Color = Theme.ink
    init(_ title: String, value: String? = nil, chevron: Bool = true, color: Color = Theme.ink) {
        self.title = title; self.value = value; self.chevron = chevron; self.color = color
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 17)).foregroundStyle(color).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let value { Text(value).font(.system(size: 16)).foregroundStyle(Theme.muted) }
            if chevron { Chevron() }
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.6)) }
}

struct CircleButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15, weight: .bold))
                .frame(width: 40, height: 40).background(.white, in: Circle())
        }
        .foregroundStyle(Theme.ink)
    }
}

/// Заглушка до раздела «Семья» (§9).
struct FamilyPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("Семья появится вместе с общим доступом к местам.").multilineTextAlignment(.center).foregroundStyle(Theme.muted)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        .navigationTitle("Моя семья").navigationBarTitleDisplayMode(.inline)
    }
}
