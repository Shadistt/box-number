import SwiftUI
import Supabase

struct ForgotPasswordView: View {
    @State var email: String
    @State private var sent = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sent {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "envelope").font(.system(size: 30, weight: .bold))
                        .frame(width: 76, height: 76).background(Theme.ink, in: Circle()).foregroundStyle(.white)
                    Text("Проверьте почту").font(.system(size: 28, weight: .heavy))
                    Text("Отправили ссылку на \(email). Она действует 30 минут.").multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity)
                Spacer()
                Button("На экран входа") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Забыли пароль?").font(.system(size: 32, weight: .heavy))
                Text("Пришлём ссылку для нового пароля на email аккаунта.").foregroundStyle(Theme.muted)
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    .padding(.horizontal, 16).frame(height: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("Отправить ссылку") { Task { await send() } }.buttonStyle(PrimaryButtonStyle())
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Spacer()
                Text("Входили через Apple или Google? Пароля нет — просто войдите тем же способом.")
                    .font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .padding(20).background(Theme.bg)
    }

    private func send() async {
        do { try await supabase.auth.resetPasswordForEmail(email, redirectTo: AppConfig.redirectURL); sent = true }
        catch { self.error = error.localizedDescription }
    }
}
