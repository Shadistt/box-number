import SwiftUI

/// Заглушка настроек первого спринта: аккаунт и выход.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section { Text("Аккаунт, тариф, семья — следующим спринтом.").foregroundStyle(Theme.muted) }
                Section { Button("Выйти", role: .destructive) { Task { await session.signOut(); dismiss() } } }
            }
            .navigationTitle("Настройки")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}
