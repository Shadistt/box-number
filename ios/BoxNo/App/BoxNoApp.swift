import SwiftUI

@main
struct BoxNoApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { session.start() }
                .onOpenURL { url in
                    // Возврат из Apple/Google или из письма с кодом/ссылкой.
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
    }
}
