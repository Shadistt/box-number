import SwiftUI

/// Получатель открыл ссылку boxnumber.co/b/<код> (макет SharedInvite): кто поделился, что за место,
/// пароль, если нужен → «Открыть место» даёт доступ и ведёт к месту.
struct SharedInviteView: View {
    let code: String
    let onOpen: (AccessStore.SharedPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var place: AccessStore.SharedPlace? = nil
    @State private var needPassword = false
    @State private var password = ""
    @State private var error: String? = nil
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                if let place {
                    Image(systemName: place.kind.symbol).font(.system(size: 34, weight: .semibold))
                        .frame(width: 96, height: 96).background(Theme.tile, in: RoundedRectangle(cornerRadius: 22))
                    Text("\(place.ownerName ?? "Вам") \(place.ownerName == nil ? "открыли" : "поделился(ась)") \(place.kind.numberLabel.lowercased()) № \(place.number)")
                        .font(.system(size: 24, weight: .heavy)).multilineTextAlignment(.center)
                    Text("\(place.title.isEmpty ? place.kind.title : place.title) · \(Plural.things(place.items))").foregroundStyle(Theme.muted)
                    Text(place.role == "edit" ? "Можно смотреть и редактировать" : "Можно смотреть").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).frame(height: 28).background(Theme.fill, in: Capsule())
                    Text("Место уже в «Моих местах» с пометкой «Общее».").font(.footnote).foregroundStyle(Theme.muted)
                } else if needPassword {
                    Image(systemName: "lock").font(.system(size: 30, weight: .bold))
                        .frame(width: 72, height: 72).background(Theme.accent, in: Circle()).foregroundStyle(Theme.dark)
                    Text("Ссылка с паролем").font(.system(size: 24, weight: .heavy))
                    Text("Введите 6 цифр, которые вам сообщили отдельно.").foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    CodeBoxes(code: $password) { Task { await open() } }
                } else {
                    ProgressView()
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Spacer()
                if place != nil {
                    Button("Открыть место") { if let place { dismiss(); onOpen(place) } }.buttonStyle(PrimaryButtonStyle())
                } else if needPassword {
                    Button("Отклонить") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
            .padding(20).background(Theme.bg)
            .navigationTitle("Приглашение").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .overlay { if busy { ProgressView() } }
            .task { await open() }
        }
    }

    private func open() async {
        busy = true; defer { busy = false }; error = nil
        do {
            place = try await access.openShareLink(code: code, password: password.isEmpty ? nil : password)
            MovesStore.clearCache()
        } catch {
            let msg = "\(error)"
            if msg.contains("password") { if needPassword && !password.isEmpty { self.error = "Неверный пароль"; password = "" }; needPassword = true }
            else if msg.contains("link_off") { self.error = "Ссылка выключена или неверна" }
            else { self.error = "Не удалось открыть: \(error.localizedDescription)" }
        }
    }
}
