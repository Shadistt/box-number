import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

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
            }
        }
        .animation(.default, value: stateKey)
    }

    private var stateKey: Int {
        switch session.state { case .loading: 0; case .signedOut: 1; case .signedIn: 2 }
    }
}
