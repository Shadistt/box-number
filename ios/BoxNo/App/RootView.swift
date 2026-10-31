import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var profile = ProfileStore.shared
    @State private var openedShare: AccessStore.SharedPlace? = nil
    struct ShareCode: Identifiable { let code: String; var id: String { code } }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn(_, let isNew):
                HomeView(startEmpty: isNew)
                    .task { await profile.load() }
                if profile.loaded, profile.profile?.needsTwoFactorCheck == true {
                    TwoFactorGateView().transition(.opacity)
                }
            }
        }
        .sheet(item: Binding(get: { session.pendingShareCode.flatMap { code -> ShareCode? in if case .signedIn = session.state { return ShareCode(code: code) }; return nil } },
                             set: { if $0 == nil { session.pendingShareCode = nil } })) { c in
            SharedInviteView(code: c.code) { shared in openedShare = shared }
        }
        .sheet(item: $openedShare) { shared in
            // Место из чужого переезда: открываем его экран с «заглушкой» переезда — RLS отдаст только это место.
            NavigationStack { PlaceView(store: PlacesStore(move: .placeholder(id: shared.moveId), destinations: []), placeId: shared.placeId) }
        }
        .background(KeyboardDismissOnTap().frame(width: 0, height: 0))   // тап мимо поля — клавиатура прячется
        .animation(.default, value: stateKey)
        .animation(.default, value: profile.profile?.needsTwoFactorCheck == true)
    }

    private var stateKey: Int {
        switch session.state { case .loading: 0; case .signedOut: 1; case .signedIn: 2 }
    }
}
