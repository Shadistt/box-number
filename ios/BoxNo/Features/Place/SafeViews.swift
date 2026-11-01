import SwiftUI

/// «Сейф» (ТЗ §10а). Паттерны Mobbin: Apple Photos «Hidden» (замок, «Открыть по Face ID / ввести пароль»),
/// Cash App «Create a password» (поле + галочка Face ID).

// MARK: - Первый сейф: задать пароль (нижняя карточка)

struct SafeSetupCard: View {
    let close: () -> Void
    let onDone: () -> Void
    @State private var safe = SafeSession.shared
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var show = false
    @State private var useBiometry = true
    @State private var busy = false
    @State private var error: String?

    private var valid: Bool { password.count >= 6 && password == repeatPassword }

    var body: some View {
        Text("Пароль сейфа").font(.system(size: 22, weight: .heavy))
        Text("Содержимое сейфа шифруется на вашем iPhone этим паролем. Мы его не знаем и не храним: забудете — содержимое сейфа будет потеряно, восстановить его нельзя.")
            .font(.subheadline).foregroundStyle(Theme.muted)
        HStack(spacing: 8) {
            Group {
                if show { TextField("Пароль, не короче 6 символов", text: $password) }
                else { SecureField("Пароль, не короче 6 символов", text: $password) }
            }
            .textContentType(.newPassword).autocorrectionDisabled().textInputAutocapitalization(.never).fieldStyle().colorScheme(.light)
            Button { show.toggle() } label: { Image(systemName: show ? "eye" : "eye.slash") }.foregroundStyle(Theme.muted).frame(width: 36, height: 52)
        }
        SecureField("Ещё раз", text: $repeatPassword).textContentType(.newPassword).fieldStyle().colorScheme(.light)
        if !repeatPassword.isEmpty, repeatPassword != password { Text("Пароли не совпадают").font(.footnote).foregroundStyle(.red) }
        if safe.biometryAvailable {
            Toggle(isOn: $useBiometry) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Открывать по Face ID").font(.system(size: 16, weight: .semibold))
                    Text("Пароль всё равно нужен — если Face ID не сработает.").font(.footnote).foregroundStyle(Theme.muted)
                }
            }.tint(Theme.accent)
        }
        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        Button { Task { await submit() } } label: {
            if busy { ProgressView().tint(Theme.onInk) } else { Text("Создать сейф") }
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(!valid || busy).opacity(valid ? 1 : 0.5)
        CancelButton(action: close)
    }

    private func submit() async {
        busy = true; defer { busy = false }; error = nil
        do {
            try await safe.setup(password: password)
            if useBiometry { try? safe.enableBiometry() }
            onDone()
        } catch { self.error = "Не удалось создать сейф: \(error.localizedDescription)" }
    }
}

// MARK: - Открыть сейф паролем (нижняя карточка)

struct SafeUnlockCard: View {
    let close: () -> Void
    let onOpened: () -> Void
    @State private var safe = SafeSession.shared
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Text("Сейф закрыт").font(.system(size: 22, weight: .heavy))
        Text("Введите пароль сейфа. Он закрывается сам, когда вы уходите из приложения.").font(.subheadline).foregroundStyle(Theme.muted)
        SecureField("Пароль сейфа", text: $password).textContentType(.password).fieldStyle().colorScheme(.light)
            .focused($focused).submitLabel(.go).onSubmit { Task { await open() } }
        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        Button { Task { await open() } } label: {
            if busy { ProgressView().tint(Theme.onInk) } else { Text("Открыть") }
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(password.isEmpty || busy).opacity(password.isEmpty ? 0.5 : 1)
        if safe.biometryEnabled {
            Button { Task { if await safe.openWithBiometry() { onOpened() } } } label: { Label("Открыть по Face ID", systemImage: "faceid") }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 44)
        }
        CancelButton(action: close)
            .task { if safe.biometryEnabled, await safe.openWithBiometry() { onOpened() } else { focused = true } }
    }

    private func open() async {
        busy = true; defer { busy = false }; error = nil
        do {
            if try await safe.open(password: password) { onOpened() }
            else { error = "Пароль не подошёл"; password = "" }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Содержимое закрытого сейфа на экране места

struct SafeLockedView: View {
    let onUnlock: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(width: 84, height: 84).background(Theme.card, in: Circle())
            Text("Сейф закрыт").font(.system(size: 20, weight: .heavy))
            Text("Вещи и фото зашифрованы на этом iPhone.\nОткройте сейф, чтобы их увидеть.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button(SafeSession.shared.biometryEnabled ? "Открыть по Face ID или паролю" : "Ввести пароль", action: onUnlock)
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24).padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }
}
