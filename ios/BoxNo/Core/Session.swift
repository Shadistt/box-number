import Foundation
import Supabase
import Observation

/// Состояние входа. Слушает Supabase Auth и решает, какой корневой экран показывать.
@MainActor
@Observable
final class SessionStore {
    enum State { case loading, signedOut, signedIn(userID: UUID, isNew: Bool) }

    var state: State = .loading
    /// Код из ссылки boxnumber.co/b/<код> (или boxno://b/<код>) — показать приглашение, когда пользователь вошёл.
    var pendingShareCode: String?

    /// true, если ссылка наша.
    func handle(url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[parts.count - 2] == "b" else { return false }
        let host = url.host ?? ""
        guard url.scheme == "boxno" || host.hasSuffix("boxnumber.co") else { return false }
        pendingShareCode = parts.last; return true
    }
    private var listener: Task<Void, Never>?

    func start() {
        listener?.cancel()
        listener = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let s = session, !(event == .initialSession && s.isExpired) {
                        let isNew = event == .signedIn && (s.user.createdAt.timeIntervalSinceNow > -120)
                        state = .signedIn(userID: s.user.id, isNew: isNew)
                    } else {
                        state = .signedOut
                    }
                case .signedOut, .userDeleted:
                    state = .signedOut
                default:
                    break
                }
            }
        }
    }

    func signOut() async {
        MovesStore.clearCache()
        ProfileStore.shared.clear()
        AccessStore.shared.clear()
        try? await supabase.auth.signOut()
    }
}
