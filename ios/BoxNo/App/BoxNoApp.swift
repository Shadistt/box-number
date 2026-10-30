import SwiftUI
import GoogleSignIn

@main
struct BoxNoApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { session.start() }
                .onOpenURL { url in
                    // Возврат из Google Sign-In или из письма со ссылкой.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
    }
}
