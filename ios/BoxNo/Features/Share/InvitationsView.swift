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
                        InitialsAvatar(name: inv.inviterName, seed: inv.inviterId)
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
                    Text("Не знаете \(inv.inviterName)? Заблокируйте — приглашения от \(inv.inviterEmail) больше не будут приходить. Человек об этом не узнает.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Button("Заблокировать") { Task { await block(inv) } }.buttonStyle(PrimaryButtonStyle(fill: .red))
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

// MARK: - Настройки → Заблокированные

struct BlockedView: View {
    @State private var access = AccessStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if access.blocks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text("Здесь пусто").font(.headline)
                        Text("Заблокировать можно, когда отклоняете приглашение.").font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    SettingsCard {
                        ForEach(Array(access.blocks.enumerated()), id: \.element.id) { i, b in
                            if i > 0 { Divider().padding(.leading, 16) }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name ?? b.email).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                    Text((b.name == nil ? "" : b.email + " · ") + "с \(b.createdAt.formatted(.dateTime.day().month()))").font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Button("Разблокировать") { Task { try? await access.unblock(b.id) } }
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12).frame(height: 34).background(Theme.fill, in: Capsule())
                            }
                            .padding(16)
                        }
                    }
                    Text("Заблокированные не могут приглашать вас в семью, переезды и места. Они об этом не знают — их приглашения просто не доходят.")
                        .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Заблокированные").navigationBarTitleDisplayMode(.inline)
        .task { await access.loadBlocks() }
    }
}
