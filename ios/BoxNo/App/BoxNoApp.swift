import SwiftUI
import GoogleSignIn

@main
struct BoxNoApp: App {
    @State private var session = SessionStore()
    @AppStorage(AppTheme.key) private var theme: String = AppTheme.light.rawValue   // по умолчанию светлая, пока тёмную не отсмотрели

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme((AppTheme(rawValue: theme) ?? .system).scheme)   // nil = как в системе
                .tint(Theme.ink)
                .task { session.start() }
                .onOpenURL { url in
                    // Возврат из Google Sign-In или из письма со ссылкой.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if session.handle(url: url) { return }
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
    }
}
