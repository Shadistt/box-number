import SwiftUI
import Supabase

/// Удаление аккаунта (макеты DeleteAccount / AccountDeleted). Подписки пока нет — блок про App Store не показываем.
struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var store = ProfileStore.shared
    @State private var agreed = false
    @State private var confirm = false
    @State private var busy = false
    @State private var deleted = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            if deleted { deletedBody } else { formBody }
        }
        .background(Theme.bg)
        .navigationTitle(deleted ? "Аккаунт удалён" : "Удаление аккаунта").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(deleted)
        .confirmationDialog("Удалить навсегда?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Удалить навсегда", role: .destructive) { Task { await deleteAccount() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Восстановить данные будет нельзя.") }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Удалить аккаунт?").font(.system(size: 26, weight: .heavy))
            Text("Навсегда удалится всё — и с телефона, и из облака:").foregroundStyle(Theme.muted)
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    bullet("shippingbox", Plural.places(store.usage?.places ?? 0) + " с лейблами")
                    Divider().padding(.leading, 56)
                    bullet("photo", "Все фотографии" + ((store.usage?.photos ?? 0) > 0 ? " — \(store.usage!.photos)" : ""))
                    Divider().padding(.leading, 56)
                    bullet("text.alignleft", "Все вещи с подписями")
                    Divider().padding(.leading, 56)
                    bullet("person.2", "Доступ к общим местам и история")
                }
            }
            Text("Восстановить данные будет нельзя.").font(.subheadline.weight(.semibold))
            Button { agreed.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(agreed ? Theme.accent : Theme.muted)
                    Text("Понимаю, что это нельзя отменить").foregroundStyle(Theme.ink)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button { confirm = true } label: {
                if busy { ProgressView().tint(.white) } else { Text("Удалить навсегда") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: .red)).disabled(!agreed || busy).opacity(agreed ? 1 : 0.5)
        }
        .padding(16)
    }

    private var deletedBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark").font(.system(size: 30, weight: .bold))
                .frame(width: 72, height: 72).background(Theme.ink, in: Circle()).foregroundStyle(.white)
            Text("Аккаунт удалён").font(.system(size: 26, weight: .heavy))
            Text("Коробки, вещи и фото удалены с телефона и из облака. Люди, с которыми вы делились коробками, больше их не видят.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
            Button("На экран входа") { Task { await session.signOut() } }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(16).padding(.top, 60)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 28).foregroundStyle(Theme.muted)
            Text(text)
            Spacer()
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private func deleteAccount() async {
        busy = true; defer { busy = false }; error = nil
        do {
            try await supabase.functions.invoke("delete-account")
            // Локальные данные: кеш переездов, фото, аватар.
            MovesStore.clearCache()
            ProfileStore.shared.clear()
            deleted = true
        } catch { self.error = "Не удалось удалить аккаунт. Проверьте сеть или напишите в поддержку." }
    }
}
