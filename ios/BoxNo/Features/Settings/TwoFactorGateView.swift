import SwiftUI
import Supabase

/// Двухфакторная проверка при входе: раз в 30 дней просим код из письма (profiles.two_factor).
/// Проверка на стороне приложения: пока не введён код, главный экран закрыт этим экраном.
struct TwoFactorGateView: View {
    @Environment(SessionStore.self) private var session
    @State private var store = ProfileStore.shared
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 30, weight: .bold))
                .frame(width: 72, height: 72).background(Theme.accent, in: Circle()).foregroundStyle(Theme.ink)
            Text("Подтвердите, что это вы").font(.system(size: 28, weight: .heavy)).multilineTextAlignment(.center)
            Text("Раз в 30 дней просим код. Отправили его на \(store.profile?.email ?? "ваш email") — iPhone подставит код сам.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
            if sent {
                CodeBoxes(code: $code) { Task { await verify() } }
                Text(busy ? "Проверяем…" : "Код действует 15 минут.").font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ProgressView()
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Spacer()
            Button("Отправить код ещё раз") { Task { await send() } }.foregroundStyle(Theme.muted).disabled(!sent)
            Button("Выйти") { Task { await session.signOut() } }.foregroundStyle(Theme.muted)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        .task { await send() }
    }

    private func send() async {
        error = nil
        do { try await EmailCode.send(); sent = true } catch { self.error = "Не удалось отправить код: \(error.localizedDescription)" }
    }

    private func verify() async {
        busy = true; defer { busy = false }
        if await EmailCode.verify(code) { await store.markTwoFactorVerified() }
        else { error = "Код не подошёл. Проверьте письмо."; code = "" }
    }
}
