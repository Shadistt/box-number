import SwiftUI
import AuthenticationServices
import Supabase
import GoogleSignIn

/// Главный экран входа: Apple, Google, email.
struct AuthView: View {
    @State private var showEmail = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                Text("Box ")
                    .font(.system(size: 44, weight: .heavy)) +
                Text("Nº").font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.accent)
                Text("Коробка — это номер маркером.\nВсё остальное — в приложении.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
                Spacer()

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))

                Button("Продолжить с Google") { Task { await signInGoogle() } }
                    .buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.ink))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))

                Button("Email и пароль") { showEmail = true }
                    .buttonStyle(PrimaryButtonStyle(fill: .clear, ink: Theme.ink))

                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(20)
            .background(Theme.bg)
            .navigationDestination(isPresented: $showEmail) { EmailAuthView() }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return }
        do {
            try await supabase.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token))
        } catch { self.error = error.localizedDescription }
    }

    /// Нативный Google Sign-In → id_token → Supabase.
    private func signInGoogle() async {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: AppConfig.googleClientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else { throw AuthError.noToken }
            try await supabase.auth.signInWithIdToken(credentials: .init(
                provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString))
        } catch let e as GIDSignInError where e.code == .canceled {
            // пользователь закрыл окно — не ошибка
        } catch { self.error = error.localizedDescription }
    }

    enum AuthError: LocalizedError {
        case noToken
        var errorDescription: String? { "Google не вернул токен" }
    }
}
