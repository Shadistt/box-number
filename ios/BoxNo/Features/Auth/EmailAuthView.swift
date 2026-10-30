import SwiftUI
import Supabase

/// Вход / регистрация по email. Регистрация → экран кода.
struct EmailAuthView: View {
    enum Mode: String, CaseIterable { case login = "Вход", signup = "Регистрация" }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @State private var goConfirm = false
    @FocusState private var focus: Field?
    enum Field { case email, password, password2 }

    private var valid: Bool {
        let okEmail = email.contains("@") && email.contains(".")
        let okPass = password.count >= 8 && password.contains(where: \.isNumber)
        return mode == .login ? (okEmail && !password.isEmpty) : (okEmail && okPass && password == password2)
    }

    var body: some View {
        // Заголовок вне ScrollView: при появлении клавиатуры прокручивается только форма, шапка не прыгает.
        VStack(alignment: .leading, spacing: 16) {
            Text("Email и пароль").font(.system(size: 32, weight: .heavy))
            Text(mode == .login ? "Войдите, чтобы увидеть свои места." : "Ваши места — на всех устройствах.")
                .foregroundStyle(Theme.muted).lineLimit(1)

            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in focus = nil }   // без фокуса автозаполнение паролей не дёргает экран

            ScrollView(showsIndicators: false) { VStack(alignment: .leading, spacing: 16) {
            LabeledField("Email") { TextField("", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .email) }
            LabeledField("Пароль") {
                HStack {
                    Group {
                        if showPassword { TextField("Не меньше 8 символов", text: $password) }
                        else { SecureField("Не меньше 8 символов", text: $password) }
                    }.textContentType(mode == .login ? .password : .newPassword).focused($focus, equals: .password)
                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye" : "eye.slash") }
                        .foregroundStyle(Theme.muted)
                }
            }
            if mode == .signup {
                LabeledField("Ещё раз") { SecureField("Повторите пароль", text: $password2).textContentType(.newPassword).focused($focus, equals: .password2) }
                Text("Минимум 8 символов, хотя бы одна цифра. Пришлём код для подтверждения — iPhone подставит его сам.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                NavigationLink("Забыли пароль?") { ForgotPasswordView(email: email) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button(mode == .login ? "Войти" : "Создать аккаунт") { Task { await submit() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!valid || busy)
                .opacity(valid ? 1 : 0.4)

            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            } }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(20)
        .background(Theme.bg)
        .navigationDestination(isPresented: $goConfirm) { ConfirmEmailView(email: email) }
    }

    private func submit() async {
        busy = true; defer { busy = false }; error = nil
        do {
            if mode == .login {
                try await supabase.auth.signIn(email: email, password: password)
            } else {
                try await supabase.auth.signUp(email: email, password: password)
                goConfirm = true
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// Подпись над полем + белая рамка. Общая для экранов входа.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            content
                .padding(.horizontal, 16).frame(height: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        }
    }
}
