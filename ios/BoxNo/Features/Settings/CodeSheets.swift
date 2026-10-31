import SwiftUI
import Supabase

/// Шесть клеток кода из письма (как на экране подтверждения email) — переиспользуется в настройках.
struct CodeBoxes: View {
    @Binding var code: String
    var onFilled: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                    Text(ch).font(.system(size: 26, weight: .bold))
                        .frame(width: 46, height: 58)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(i == code.count ? Theme.accent : .clear, lineWidth: 2))
                }
            }
            // Невидимое поле во всю ширину клеток: автоподстановка кода из «Почты» вставляет текст в поле-первый-ответчик,
            // а поле высотой 1 pt она игнорировала.
            .overlay {
                TextField("", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($focused).foregroundStyle(.clear).tint(.clear)
                    .accentColor(.clear)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                        if code.count == 6 { onFilled() }
                    }
            }
        }
        .task { focused = true }
    }
}

/// Отправка кода на email текущего пользователя (одноразовый код, без создания пользователя)
/// и проверка. Возвращает true, если код подошёл.
enum EmailCode {
    static func send() async throws {
        guard let email = supabase.auth.currentUser?.email else { throw URLError(.userAuthenticationRequired) }
        try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: false)
    }
    static func verify(_ code: String) async -> Bool {
        guard let email = supabase.auth.currentUser?.email else { return false }
        do { _ = try await supabase.auth.verifyOTP(email: email, token: code, type: .email); return true } catch { return false }
    }
}

// MARK: - Пароль: задать или изменить (нижняя карточка)

struct PasswordCard: View {
    let close: () -> Void
    @State private var store = ProfileStore.shared
    @State private var current = ""
    @State private var new = ""
    @State private var repeatNew = ""
    @State private var showNew = false
    @State private var code = ""
    @State private var stage: Stage = .form
    @State private var busy = false
    @State private var error: String?
    enum Stage { case form, code, done }

    private var hasPassword: Bool { store.hasPassword }
    private var email: String { store.profile?.email ?? "" }
    private var valid: Bool { new.count >= 8 && new == repeatNew && (!hasPassword || !current.isEmpty) }

    var body: some View {
        switch stage {
        case .form:
            Text(hasPassword ? "Изменить пароль" : "Задать пароль").font(.system(size: 22, weight: .heavy))
            Text(hasPassword
                 ? "Введите текущий пароль и новый. Если текущий забыли — закройте и нажмите «Забыли пароль» на экране входа."
                 : "После этого войти можно будет по email и паролю, а Apple или Google — отвязать, если захотите.")
                .font(.subheadline).foregroundStyle(Theme.muted)
            if hasPassword {
                SecureField("Текущий пароль", text: $current).textContentType(.password).fieldStyle().colorScheme(.light)
            }
            // Поля пароля всегда в светлой схеме: автозаполнение iOS красит поле жёлтым, и в тёмной теме светлый текст пропадал.
            HStack(spacing: 8) {
                Group {
                    if showNew { TextField("Новый пароль, не короче 8 символов", text: $new) }
                    else { SecureField("Новый пароль, не короче 8 символов", text: $new) }
                }
                .textContentType(.newPassword).autocorrectionDisabled().textInputAutocapitalization(.never)
                .fieldStyle().colorScheme(.light)
                Button { showNew.toggle() } label: { Image(systemName: showNew ? "eye" : "eye.slash") }
                    .foregroundStyle(Theme.muted).frame(width: 36, height: 52)
            }
            SecureField("Ещё раз", text: $repeatNew).textContentType(.newPassword).fieldStyle().colorScheme(.light)
            if !repeatNew.isEmpty, repeatNew != new { Text("Пароли не совпадают").font(.footnote).foregroundStyle(.red) }
            if !hasPassword {
                Text("Подтвердим кодом на \(email) — iPhone подставит его сам.").font(.footnote).foregroundStyle(Theme.muted)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button(hasPassword ? "Сохранить новый пароль" : "Задать пароль") { Task { await submit() } }
                .buttonStyle(PrimaryButtonStyle()).disabled(!valid || busy).opacity(valid ? 1 : 0.5)
            CancelButton(action: close)
        case .code:
            Text("Код из письма").font(.system(size: 22, weight: .heavy))
            Text("Отправили код на \(email). Введите его, чтобы задать пароль.").font(.subheadline).foregroundStyle(Theme.muted)
            CodeBoxes(code: $code) { Task { await finishWithNonce() } }
            Text(busy ? "Проверяем…" : "Код действует 15 минут.").font(.footnote).foregroundStyle(Theme.muted)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            CancelButton(action: close)
        case .done:
            Label(hasPassword ? "Пароль изменён" : "Пароль задан", systemImage: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
            Text("Теперь входить можно по email и паролю.").font(.subheadline).foregroundStyle(Theme.muted)
            Button("Готово", action: close).buttonStyle(PrimaryButtonStyle())
        }
    }

    private func submit() async {
        busy = true; defer { busy = false }; error = nil
        do {
            if hasPassword {
                // Supabase не проверяет текущий пароль при смене — проверяем сами повторным входом.
                _ = try await supabase.auth.signIn(email: email, password: current)
                _ = try await supabase.auth.update(user: UserAttributes(password: new))
                await store.load()
                stage = .done
            } else {
                // Пароля нет: подтверждение кодом (reauthentication nonce), затем update(password:nonce:).
                try await supabase.auth.reauthenticate()
                stage = .code
            }
        } catch {
            self.error = hasPassword ? "Текущий пароль не подошёл." : "Не удалось отправить код: \(error.localizedDescription)"
        }
    }

    private func finishWithNonce() async {
        busy = true; defer { busy = false }; error = nil
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: new, nonce: code))
            await store.load()          // profiles.has_password обновился триггером — строка «Пароль» покажет ••••••••
            stage = .done
        } catch { self.error = "Код не подошёл. Проверьте письмо."; code = "" }
    }
}

// MARK: - Двухфакторная защита: включить / выключить кодом на email (нижняя карточка)

struct TwoFactorCard: View {
    let close: () -> Void
    @State private var store = ProfileStore.shared
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var error: String?

    private var turningOn: Bool { !(store.profile?.twoFactor ?? false) }

    var body: some View {
        Text(turningOn ? "Включить двухфакторную защиту" : "Выключить двухфакторную защиту").font(.system(size: 22, weight: .heavy))
        if sent {
            Text("Отправили код на \(store.profile?.email ?? ""). Введите его, чтобы подтвердить.").font(.subheadline).foregroundStyle(Theme.muted)
            CodeBoxes(code: $code) { Task { await verify() } }
            Text(busy ? (turningOn ? "Включаем…" : "Выключаем…") : "Код действует 15 минут.").font(.footnote).foregroundStyle(Theme.muted)
        } else {
            Text(turningOn ? "Раз в 30 дней при входе попросим код из письма. Сначала подтвердим кодом, что почта ваша."
                           : "Подтвердите кодом из письма, и при входе код спрашивать перестанем.")
                .font(.subheadline).foregroundStyle(Theme.muted)
            Text("Пришлём код на \(store.profile?.email ?? "").").font(.footnote).foregroundStyle(Theme.muted)
        }
        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        if !sent {
            Button { Task { await send() } } label: {
                if busy { ProgressView().tint(Theme.onInk) } else { Text("Отправить код") }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(busy)
        }
        CancelButton(action: close)
    }

    private func send() async {
        busy = true; defer { busy = false }; error = nil
        do { try await EmailCode.send(); withAnimation(.snappy) { sent = true } }
        catch { self.error = "Не удалось отправить код: \(error.localizedDescription)" }
    }

    private func verify() async {
        busy = true; defer { busy = false }
        if await EmailCode.verify(code) {
            await store.setTwoFactor(turningOn)
            close()
        } else { error = "Код не подошёл. Проверьте письмо."; code = "" }
    }
}

/// Вторичная «Отмена» под главной кнопкой: своя высота 48 и отступ — не липнет к кнопке.
struct CancelButton: View {
    var title = "Отмена"
    let action: () -> Void
    var body: some View {
        Button(title, action: action).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 48).padding(.top, 6)
    }
}

extension View {
    func fieldStyle() -> some View {
        self.font(.system(size: 17)).padding(.horizontal, 14).frame(height: 52)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14))
    }
}
