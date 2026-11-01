import SwiftUI

/// §9 «Кто видит переезд» (макет MoveFamily): семья с переключателем на каждого, роль у включённых,
/// «ждём» у приглашённых; «Добавить нового» — email → в семью и сразу в этот переезд.
struct MoveFamilyView: View {
    let move: Move
    let placesCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var rows: [AccessRow] = []
    @State private var email = ""
    @State private var busy = false
    @State private var toast: String? = nil
    @State private var inviteContacts = false

    private var onCount: Int { access.others.filter { m in rows.contains { $0.userId == m.userId && m.userId != nil } || (m.invitedEmail != nil && rows.contains { $0.invitedEmail == m.invitedEmail }) }.count }
    private var validEmail: Bool { let e = email.trimmingCharacters(in: .whitespaces); return e.contains("@") && e.contains(".") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(move.displayTitle(destinations: [])) · \(Plural.places(placesCount)). Только для этого переезда: другие переезды не затрагиваются.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)

                    SectionTitle("Семья · \(onCount) из \(access.others.count) видят")
                    SettingsCard {
                        if access.others.isEmpty {
                            Text("В семье пока никого. Добавьте первого ниже.").font(.subheadline).foregroundStyle(Theme.muted).padding(16)
                        }
                        ForEach(Array(access.others.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Divider().padding(.leading, 68) }
                            memberRow(m)
                        }
                    }

                    SectionTitle("Добавить нового")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().fieldStyle()
                                Button { inviteContacts = true } label: {
                                    Image(systemName: "book.closed").font(.system(size: 18, weight: .semibold))
                                        .frame(width: 52, height: 52).background(Theme.fill, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.ink)
                                }
                            }
                            Button { Task { await invite(email) } } label: {
                                if busy { ProgressView().tint(Theme.onInk) } else { Text("Пригласить и открыть этот переезд") }
                            }
                            .buttonStyle(PrimaryButtonStyle()).disabled(!validEmail || busy).opacity(validEmail ? 1 : 0.5)
                            Text("Человек попадёт в семью и сразу увидит этот переезд. Пока не принял приглашение, он в списке с пометкой «ждём».")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                    }
                    Text("Новые места этого переезда открываются выбранным людям сами. Убрать человека из семьи целиком — Настройки → Семья.")
                        .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Theme.bg).scrollDismissesKeyboard(.interactively)
            .navigationTitle("Кто видит переезд").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onInk)
                        .padding(.horizontal, 18).frame(height: 48).background(Theme.ink, in: Capsule()).padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: toast)
            .sheet(isPresented: $inviteContacts) {
                ContactsPicker { emails in if let e = emails.first { email = e } }.ignoresSafeArea()
            }
            .task { await access.loadFamily(); rows = await access.moveAccess(move.id) }
        }
    }

    private func memberRow(_ m: FamilyMember) -> some View {
        let row = rows.first { ($0.userId != nil && $0.userId == m.userId) || ($0.invitedEmail != nil && $0.invitedEmail == m.invitedEmail) }
        let on = row != nil
        let pending = m.status == "invited" || m.status == "pending"
        let declined = m.status == "declined" || row?.status == "declined"
        return HStack(spacing: 12) {
            PersonAvatar(person: access.person(m.userId), fallback: String((m.invitedEmail ?? "?").prefix(1)).uppercased())
            VStack(alignment: .leading, spacing: 2) {
                Text(access.name(m)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(declined ? "отклонил(а) приглашение" : pending ? "ждём ответа на приглашение" : on ? (row?.role == "edit" ? "видит и редактирует" : "только смотрит") : "не видит этот переезд")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer()
            if on, let row, !pending {
                Button(row.role == "edit" ? "Редактирует" : "Смотрит") { Task { await toggleRole(row) } }
                    .font(.footnote.weight(.semibold)).padding(.horizontal, 10).frame(height: 30)
                    .background(Theme.fill, in: Capsule()).foregroundStyle(Theme.ink)
            }
            Toggle("", isOn: Binding(get: { on }, set: { v in Task { await set(m, on: v, existing: row) } })).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func set(_ m: FamilyMember, on: Bool, existing: AccessRow?) async {
        do {
            if on {
                if let u = m.userId { try await access.grantMove(move.id, userId: u, role: access.familyAutoRole) }
                else if let e = m.invitedEmail { _ = try await access.invite(email: e, kind: "move", moveId: move.id, role: access.familyAutoRole) }
                flash("\(access.name(m)) теперь видит переезд")
            } else if let existing {
                try await access.revoke(table: "move_access", id: existing.id)
                flash("\(access.name(m)) больше не видит переезд")
            }
            rows = await access.moveAccess(move.id)
        } catch { flash("Не получилось: \(error.localizedDescription)") }
    }

    private func toggleRole(_ r: AccessRow) async {
        do { try await access.setRole(table: "move_access", id: r.id, role: r.role == "edit" ? "view" : "edit"); rows = await access.moveAccess(move.id) }
        catch { flash("Не получилось") }
    }

    private func invite(_ e: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await access.invite(email: e.trimmingCharacters(in: .whitespaces), kind: "move", moveId: move.id, role: access.familyAutoRole)
            email = ""
            await access.loadFamily(); rows = await access.moveAccess(move.id)
            flash("Приглашение отправлено на \(e)")
        } catch { flash("Не получилось: \(error.localizedDescription)") }
    }
    private func flash(_ t: String) { toast = t; Task { try? await Task.sleep(for: .seconds(2.5)); if toast == t { toast = nil } } }
}
