import SwiftUI
import Supabase

/// Код из письма, 6 цифр, автоподстановка. После успеха — «Продолжить» и автопереход через 3 с.
struct ConfirmEmailView: View {
    let email: String
    @State private var code = ""
    @State private var done = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: done ? "checkmark" : "envelope")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 72, height: 72)
                .background(done ? Theme.ink : Theme.accent, in: Circle())
                .foregroundStyle(done ? .white : Theme.ink)
            Text(done ? "Email подтверждён" : "Подтвердите email").font(.system(size: 28, weight: .heavy))
            Text(done ? "Аккаунт привязан к \(email). Открываем главный экран."
                      : "Мы отправили код на \(email). Откройте письмо — iPhone подставит код сам.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted)

            if !done {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                        Text(ch).font(.system(size: 26, weight: .bold))
                            .frame(width: 48, height: 60)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(i == code.count ? Theme.accent : .clear, lineWidth: 2))
                    }
                }
                .overlay {
                    TextField("", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focused).foregroundStyle(.clear).tint(.clear)
                        .accentColor(.clear)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(6))
                            if code.count == 6 { Task { await verify() } }
                        }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Spacer()
            if done {
                AutoAdvanceBar(seconds: 3) { /* RootView переключит экран сам по сессии */ }
            }
        }
        .padding(20).background(Theme.bg)
        .navigationBarBackButtonHidden(done)
        .task { focused = true }
    }

    private func verify() async {
        do {
            try await supabase.auth.verifyOTP(email: email, token: code, type: .signup)
            done = true
        } catch { self.error = "Код не подошёл. Проверьте письмо."; code = "" }
    }
}

/// Бегунок автоперехода под кнопкой «Продолжить».
struct AutoAdvanceBar: View {
    let seconds: Double
    let onDone: () -> Void
    @State private var progress: CGFloat = 1

    var body: some View {
        VStack(spacing: 10) {
            Button("Продолжить", action: onDone).buttonStyle(PrimaryButtonStyle())
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 3).fill(Theme.line)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: g.size.width * progress)
                    }
            }.frame(height: 5)
            Text("Дальше само через \(Int(seconds)) секунды — или нажмите").font(.footnote).foregroundStyle(Theme.muted)
        }
        .onAppear { withAnimation(.linear(duration: seconds)) { progress = 0 } }
        .task { try? await Task.sleep(for: .seconds(seconds)); onDone() }
    }
}
