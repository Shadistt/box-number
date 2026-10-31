import SwiftUI

/// Главный: «Box Nº» + шестерёнка, сегменты Переезды / Хранение / Посылки.
/// Хранение и Посылки — неактивны на первом этапе.
struct HomeView: View {
    enum Tab: String, CaseIterable { case moves = "Переезды", storage = "Хранение", parcels = "Посылки" }
    let startEmpty: Bool
    @State private var tab: Tab = .moves
    @State private var showSettings = false
    @State private var showSoon = false

    var body: some View {
        NavigationStack {
            // Шапка — поверх списка на «матовом стекле»: карточки уходят под неё с размытием, а не обрезаются линией.
            MovesListView(startEmpty: startEmpty)
                .padding(.horizontal, 16)
                .safeAreaInset(edge: .top, spacing: 0) {
                    header.padding(.horizontal, 16).padding(.bottom, 10)
                        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
                }
            .background(Theme.bg)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Скоро", isPresented: $showSoon) { Button("Ок") {} } message: {
                Text("Хранение и Посылки появятся после переездов.")
            }
        }
    }

    private var header: some View {
            VStack(spacing: 16) {
                HStack {
                    (Text("Box ") + Text("Nº").foregroundStyle(Theme.accent))
                        .font(.system(size: 28, weight: .heavy))
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44).background(Theme.card, in: Circle())
                    }.foregroundStyle(Theme.ink)
                }

                HStack(spacing: 4) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        let active = t == .moves
                        Button {
                            if active { tab = t } else { showSoon = true }
                        } label: {
                            Text(t.rawValue).font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(tab == t ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(active ? Theme.ink : Theme.muted.opacity(0.5))
                    }
                }
                .padding(4).background(Theme.fill, in: RoundedRectangle(cornerRadius: 13))
            }
    }
}
