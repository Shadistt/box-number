import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Supabase
import GoogleSignIn

/// Главный экран входа: Apple, Google, email.
struct AuthView: View {
    @State private var showEmail = false
    @State private var error: String?
    @State private var busy = false
    @State private var appleNonce = ""

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
                    appleNonce = Self.randomNonce()
                    request.nonce = Self.sha256(appleNonce)
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))

                Button { Task { await signInGoogle() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(Theme.ink) }
                        Text("Продолжить с Google")
                    }
                }
                    .buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.ink))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
                    .disabled(busy)

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
        busy = true; defer { busy = false }
        do {
            try await supabase.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: appleNonce))
        } catch { self.error = error.localizedDescription }
    }

    /// Нативный Google Sign-In → id_token → Supabase.
    private func signInGoogle() async {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        busy = true; defer { busy = false }
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

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum AuthError: LocalizedError {
        case noToken
        var errorDescription: String? { "Google не вернул токен" }
    }
}
