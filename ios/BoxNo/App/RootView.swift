import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var profile = ProfileStore.shared

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
        .background(KeyboardDismissOnTap().frame(width: 0, height: 0))   // тап мимо поля — клавиатура прячется
        .animation(.default, value: stateKey)
        .animation(.default, value: profile.profile?.needsTwoFactorCheck == true)
    }

    private var stateKey: Int {
        switch session.state { case .loading: 0; case .signedOut: 1; case .signedIn: 2 }
    }
}
