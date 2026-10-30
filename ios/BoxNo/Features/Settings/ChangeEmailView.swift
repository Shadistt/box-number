import SwiftUI
import Supabase

/// Смена email (макет ChangeEmail): новый адрес → код на него → «Email изменён».
/// На сервере выключено двойное подтверждение: код приходит только на новый адрес,
/// а на старый уходит уведомление (шаблон email_changed).
struct ChangeEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProfileStore.shared
    @State private var email = ""
    @State private var code = ""
    @State private var stage: Stage = .form
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool
    enum Stage { case form, code, done }

    private var current: String { store.profile?.email ?? "" }
    private var valid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        return e.contains("@") && e.contains(".") && e != current.lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch stage {
                case .form:
                    SectionTitle("Новый email")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Сейчас: \(current)").font(.footnote).foregroundStyle(Theme.muted)
                            TextField("Новый адрес", text: $email)
                                .keyboardType(.emailAddress).textContentType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused).fieldStyle()
                            Text("Пришлём код на новый адрес. Пока не введёте код, остаётся старый.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button("Отправить код") { Task { await send() } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!valid || busy).opacity(valid ? 1 : 0.5)
                    Text("Вход через Apple и Google не изменится — у них свои адреса.")
                        .font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                case .code:
                    SectionTitle("Код из письма")
                    SettingsCard {
                        VStack(spacing: 12) {
                            Text("Отправили на \(email)").font(.subheadline).foregroundStyle(Theme.muted)
                            CodeBoxes(code: $code) { Task { await verify() } }
                            Text(busy ? "Проверяем…" : "Код действует 15 минут. Не пришёл — проверьте «Спам».")
                                .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                        .padding(16).frame(maxWidth: .infinity)
                    }
                    Button("Изменить адрес") { stage = .form; code = ""; error = nil }
                        .frame(maxWidth: .infinity).foregroundStyle(Theme.muted)
                case .done:
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark").font(.system(size: 30, weight: .bold))
                            .frame(width: 72, height: 72).background(Theme.ink, in: Circle()).foregroundStyle(.white)
                        Text("Email изменён").font(.system(size: 26, weight: .heavy))
                        Text("Теперь входите с \(email). На старый адрес отправили уведомление.")
                            .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                        Button("Готово") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Email").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(stage == .done)
        .task { focused = true }
    }

    private func send() async {
        busy = true; defer { busy = false }; error = nil
        email = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: email))
            stage = .code
        } catch { self.error = "Не удалось отправить код: \(error.localizedDescription)" }
    }

    private func verify() async {
        busy = true; defer { busy = false }; error = nil
        do {
            _ = try await supabase.auth.verifyOTP(email: email, token: code, type: .emailChange)
            await store.setEmail(email)
            stage = .done
        } catch { self.error = "Код не подошёл. Проверьте письмо."; code = "" }
    }
}
