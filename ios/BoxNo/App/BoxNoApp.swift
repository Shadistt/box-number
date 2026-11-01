import SwiftUI
import GoogleSignIn

@main
struct BoxNoApp: App {
    @State private var session = SessionStore()
    @AppStorage(AppTheme.key) private var theme: String = AppTheme.light.rawValue   // по умолчанию светлая, пока тёмную не отсмотрели

    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme((AppTheme(rawValue: theme) ?? .system).scheme)   // nil = как в системе
                // Открытые sheet'ы (Настройки → Тема) — отдельные презентации и preferredColorScheme не наследуют:
                // переключаем стиль окна, тогда меняется всё сразу.
                .onChange(of: theme, initial: true) { _, t in
                    let style: UIUserInterfaceStyle = switch AppTheme(rawValue: t) ?? .system { case .light: .light; case .dark: .dark; case .system: .unspecified }
                    for s in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) { for w in s.windows { w.overrideUserInterfaceStyle = style } }
                }
                .tint(Theme.ink)
                .task { session.start() }
                // Сейф закрывается, как только приложение уходит с экрана (ТЗ §10а).
                .onChange(of: scenePhase) { _, p in if p != .active { SafeSession.shared.lock() } }
                .onOpenURL { url in
                    // Возврат из Google Sign-In или из письма со ссылкой.
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if session.handle(url: url) { return }
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
    }
}
