import SwiftUI

/// Приглашения на главном (ТЗ §9, 01.11.2026): карточка «<Имя> приглашает вас в переезд «…»» с Принять / Отклонить
/// (паттерн Tripsy / Savee, Mobbin). После отказа — «Не знаете <имя>?» → Заблокировать (прототип сайта, mobile-backlog).
struct InvitationsSection: View {
    @State private var access = AccessStore.shared
    @State private var busy: UUID? = nil
    let onChanged: () async -> Void
    /// Отклонили — родитель показывает нижнюю карточку «Не знаете …? Заблокировать».
    let onDeclined: (AccessStore.Invitation) -> Void

    var body: some View {
        if !access.invitations.isEmpty {
            Text("ПРИГЛАШЕНИЯ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
            ForEach(access.invitations) { inv in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        InitialsAvatar(name: inv.inviterName, seed: inv.inviterId ?? inv.id)
                        VStack(alignment: .leading, spacing: 3) {
                            (Text(inv.inviterName).fontWeight(.bold) + Text(" \(inv.text)")).font(.system(size: 16)).foregroundStyle(Theme.ink)
                            Text("\(inv.inviterEmail) · \(inv.roleText)").font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Отклонить") { Task { await respond(inv, accept: false) } }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.fill, ink: Theme.ink))
                        Button {
                            Task { await respond(inv, accept: true) }
                        } label: { if busy == inv.id { ProgressView().tint(Theme.onInk) } else { Text("Принять") } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .disabled(busy != nil)
                }
                .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.5), lineWidth: 1.5))
            }
        }
    }

    private func respond(_ inv: AccessStore.Invitation, accept: Bool) async {
        busy = inv.id; defer { busy = nil }
        do {
            try await access.respond(inv, accept: accept)
            await onChanged()
            if !accept { onDeclined(inv) }
        } catch { print("respond:", error) }
    }
}

/// Нижняя карточка после отказа + плашка «заблокирована · Отменить». Вешается на корень главного экрана.
struct BlockAfterDeclineOverlay: View {
    @Binding var invitation: AccessStore.Invitation?
    @State private var access = AccessStore.shared
    @State private var toast: (email: String, id: UUID)? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let t = toast {
                HStack(spacing: 12) {
                    Text("\(t.email) заблокирована").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button("Отменить") { Task { try? await access.unblock(t.id); withAnimation(.snappy) { toast = nil } } }
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16).frame(height: 48).foregroundStyle(Theme.onInk)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16).padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let inv = invitation {
                BottomCard(isPresented: .init(get: { invitation != nil }, set: { if !$0 { invitation = nil } })) {
                    Text("Приглашение отклонено").font(.system(size: 22, weight: .heavy))
                    Text("\(inv.inviterName) об этом не узнает — у него останется «ждём ответа». Передумаете — Настройки → Приглашения, 30 дней.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Text("Не знаете \(inv.inviterName)? Заблокируйте — приглашения от \(inv.inviterEmail) больше не будут приходить.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Button("Заблокировать") { Task { await block(inv) } }.buttonStyle(PrimaryButtonStyle(fill: .red))
                    Button("Отменить отказ") {
                        Task { try? await access.undoDecline(inv); withAnimation(.snappy) { invitation = nil } }
                    }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 44)
                    CancelButton(title: "Не нужно") { withAnimation(.snappy) { invitation = nil } }
                }
            }
        }
        .animation(.snappy, value: toast?.id)
    }

    private func block(_ inv: AccessStore.Invitation) async {
        withAnimation(.snappy) { invitation = nil }
        do {
            let id = try await access.block(email: inv.inviterEmail)
            withAnimation(.snappy) { toast = (inv.inviterEmail, id) }
            try? await Task.sleep(for: .seconds(5))
            if toast?.id == id { withAnimation(.snappy) { toast = nil } }
        } catch { print("block:", error) }
    }
}

/// Круг с инициалами, цвет по id (как PersonAvatar без фото).
struct InitialsAvatar: View {
    let name: String
    let seed: UUID
    var size: CGFloat = 44
    private static let colors: [Color] = [Theme.accent, Color(hex: 0x3B4D74), Color(hex: 0x4D5F4A), Color(hex: 0x8C6BB1), Color(hex: 0xC9A27A)]
    var body: some View {
        let i = Int(seed.uuidString.first?.asciiValue ?? 0) % Self.colors.count
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        Text(initials.isEmpty ? "?" : initials).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size).background(Self.colors[i], in: Circle())
    }
}

// MARK: - Настройки → Приглашения (02.11.2026): все приглашения мне со статусами; тап по статусу — изменить.
// Паттерн Instacart / Partiful (Mobbin): чипы-фильтры со счётчиками, цветной статус справа, лист снизу с действиями.

struct InvitationsListView: View {
    @State private var access = AccessStore.shared
    @State private var filter = "all"
    @State private var selected: AccessStore.Invitation? = nil
    @State private var busy = false
    @State private var loaded = false

    private let filters: [(String, String)] = [("all", "Все"), ("pending", "Ждут"), ("accepted", "Принятые"), ("declined", "Отклонённые"), ("blocked", "Заблокированные")]
    private func count(_ f: String) -> Int { f == "all" ? access.allInvitations.count : access.allInvitations.filter { group($0) == f }.count }
    /// «Истекло» показываем в «Отклонённых» — действий почти нет, отдельный фильтр не нужен.
    private func group(_ i: AccessStore.Invitation) -> String { i.state == "expired" ? "declined" : i.state }
    private var rows: [AccessStore.Invitation] { filter == "all" ? access.allInvitations : access.allInvitations.filter { group($0) == filter } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Все приглашения, которые вам присылали. Тап по статусу — изменить.").font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(filters, id: \.0) { f in
                            Button { withAnimation(.snappy) { filter = f.0 } } label: {
                                HStack(spacing: 4) {
                                    Text(f.1).font(.system(size: 14, weight: .semibold))
                                    Text("\(count(f.0))").font(.system(size: 14)).foregroundStyle(filter == f.0 ? Theme.onInk.opacity(0.6) : Theme.muted)
                                }
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(filter == f.0 ? Theme.ink : Theme.card, in: Capsule()).foregroundStyle(filter == f.0 ? Theme.onInk : Theme.ink)
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)

                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.open").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text("Здесь пусто").font(.headline)
                        Text(filter == "blocked" ? "Заблокировать можно, когда отклоняете приглашение." : "Приглашения в семью, переезды и места появятся здесь.")
                            .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.top, 50)
                } else {
                    SettingsCard {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, inv in
                            if i > 0 { Divider().padding(.leading, 68) }
                            Button { selected = inv } label: { row(inv) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Приглашения").navigationBarTitleDisplayMode(.inline)
        .task { await access.loadInvitations(); loaded = true }
        .refreshable { await access.loadInvitations() }
        .overlay {
            if let inv = selected {
                BottomCard(isPresented: .init(get: { selected != nil }, set: { if !$0 { selected = nil } })) { actions(inv) }
            }
        }
        .animation(.snappy, value: selected?.id)
    }

    private func row(_ inv: AccessStore.Invitation) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: inv.inviterName, seed: inv.inviterId ?? inv.id, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.inviterName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(subtitle(inv)).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 6)
            StatusPill(state: inv.state)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }

    private func subtitle(_ inv: AccessStore.Invitation) -> String {
        let date = inv.createdAt.formatted(.dateTime.day().month())
        switch inv.state {
        case "declined": return "\(inv.what) · \(date) · можно принять ещё \(Plural.days(inv.daysLeft ?? 0))"
        case "blocked": return inv.kind == "block" ? "с \(date) · его приглашения не доходят" : "\(inv.what) · \(date) · приглашения не доходят"
        case "expired": return "\(inv.what) · \(date) · срок ответа прошёл"
        default: return "\(inv.what) · \(date)"
        }
    }

    @ViewBuilder
    private func actions(_ inv: AccessStore.Invitation) -> some View {
        Text(inv.kind == "block" ? inv.inviterName : "\(inv.inviterName) · \(inv.kind == "family" ? "в семью" : inv.kind == "move" ? "в переезд" : "место")")
            .font(.system(size: 22, weight: .heavy))
        Text(explain(inv)).font(.subheadline).foregroundStyle(Theme.muted)
        switch inv.state {
        case "pending":
            action("Принять", fill: Theme.ink, ink: Theme.onInk) { try await access.respond(inv, accept: true) }
            action("Отклонить", fill: Theme.fill, ink: Theme.ink) { try await access.respond(inv, accept: false) }
            action("Заблокировать", fill: Color.red.opacity(0.08), ink: .red) { try await access.block(email: inv.inviterEmail) }
        case "accepted":
            action(inv.kind == "family" ? "Выйти из семьи" : inv.kind == "move" ? "Выйти из переезда" : "Убрать место", fill: Color.red.opacity(0.08), ink: .red) { try await access.leave(inv) }
        case "declined":
            action("Принять", fill: Theme.ink, ink: Theme.onInk) { try await access.respond(inv, accept: true) }
            action("Заблокировать", fill: Color.red.opacity(0.08), ink: .red) { try await access.block(email: inv.inviterEmail) }
        case "expired":
            action("Заблокировать", fill: Color.red.opacity(0.08), ink: .red) { try await access.block(email: inv.inviterEmail) }
        case "blocked":
            action("Разблокировать", fill: Theme.ink, ink: Theme.onInk) { try await access.unblock(email: inv.inviterEmail) }
        default: EmptyView()
        }
        CancelButton(title: "Закрыть") { withAnimation(.snappy) { selected = nil } }
    }

    private func explain(_ inv: AccessStore.Invitation) -> String {
        let what = inv.title.map { "«\($0)», " } ?? ""
        let date = inv.createdAt.formatted(.dateTime.day().month(.wide))
        switch inv.state {
        case "pending": return "\(what)\(date). \(inv.roleText.capitalized)."
        case "accepted": return "\(what)вы приняли приглашение. Выйдете — доступ закроется; \(inv.inviterName) увидит, что вас больше нет в списке."
        case "declined": return "\(what)\(date). Вы отклонили — \(inv.inviterName) об этом не знает, у него «ждём ответа». Принять можно ещё \(Plural.days(inv.daysLeft ?? 0))."
        case "expired": return "\(what)\(date). Срок ответа прошёл. Если \(inv.inviterName) пригласит снова — приглашение появится на главном."
        case "blocked": return "Приглашения от \(inv.inviterEmail) не доходят, человек об этом не знает. Разблокируете — отклонённые при блокировке приглашения снова можно будет принять (в пределах 30 дней)."
        default: return ""
        }
    }

    private func action(_ title: String, fill: Color, ink: Color, _ run: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                busy = true; defer { busy = false }
                do { try await run(); withAnimation(.snappy) { selected = nil } } catch { print("invitation action:", error) }
            }
        } label: { Text(title) }
        .buttonStyle(PrimaryButtonStyle(fill: fill, ink: ink)).disabled(busy)
    }
}

/// Цветной статус: Ждёт — оранжевый, Принято — зелёный, Отклонено/Истекло — серый, Заблокирован — красный.
struct StatusPill: View {
    let state: String
    private var style: (String, Color, Color) {
        switch state {
        case "pending": ("Ждёт", Theme.accent.opacity(0.12), Theme.accent)
        case "accepted": ("Принято", Color.green.opacity(0.14), Color(hex: 0x2F7D46))
        case "declined": ("Отклонено", Theme.fill, Theme.muted)
        case "expired": ("Истекло", Theme.fill, Theme.muted)
        default: ("Заблокирован", Color.red.opacity(0.1), .red)
        }
    }
    var body: some View {
        HStack(spacing: 2) {
            Text(style.0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 12, weight: .bold)).padding(.horizontal, 9).frame(height: 26)
        .background(style.1, in: Capsule()).foregroundStyle(style.2)
    }
}
