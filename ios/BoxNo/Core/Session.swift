import Foundation
import Supabase
import Observation

/// Состояние входа. Слушает Supabase Auth и решает, какой корневой экран показывать.
@MainActor
@Observable
final class SessionStore {
    enum State { case loading, signedOut, signedIn(userID: UUID, isNew: Bool) }

    var state: State = .loading
    private var listener: Task<Void, Never>?

    func start() {
        listener?.cancel()
        listener = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let s = session {
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
        try? await supabase.auth.signOut()
    }
}
