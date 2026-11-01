import SwiftUI
import ContactsUI

/// §8 «Кого добавить» (макет SharePeople, вариант B): поиск по имени/email, Семья, Недавно делились,
/// Из контактов iPhone (системный выбор — доступ ко всей книге не нужен), полный email → «Пригласить по email».
/// Снизу: выбранные, роль для всех, «Добавить N человек · смотрят».
struct SharePeopleView: View {
    let placeId: UUID
    let placeTitle: String
    let existing: [UUID]
    let onDone: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var query = ""
    @State private var picked: [Pick] = []
    @State private var role = "view"
    @State private var busy = false
    @State private var error: String? = nil
    @State private var contacts = false
    @FocusState private var focused: Bool

    enum Pick: Hashable, Identifiable {
        case user(UUID), email(String)
        var id: String { switch self { case .user(let u): u.uuidString; case .email(let e): e } }
    }

    private var q: String { query.trimmingCharacters(in: .whitespaces) }
    private var isEmail: Bool { q.isValidEmail }
    private var familyRows: [FamilyMember] { access.others.filter { matches($0) } }
    private var recentRows: [UUID] { access.recent.filter { u in !access.family.contains(where: { f in f.userId == u }) && matches(u) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(placeTitle).font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    SearchField(text: $query, placeholder: "Имя или email", focused: $focused)

                    if isEmail && !picked.contains(.email(q.lowercased())) {
                        SettingsCard {
                            Button { toggle(.email(q.lowercased())); query = "" } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "envelope").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40).background(Theme.fill, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Пригласить по email").font(.system(size: 16, weight: .semibold))
                                        Text("\(q) · приложение не обязательно").font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                }
                                .padding(12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }

                    if !familyRows.isEmpty {
                        SectionTitle("Семья")
                        SettingsCard {
                            ForEach(Array(familyRows.enumerated()), id: \.element.id) { i, m in
                                if i > 0 { Divider().padding(.leading, 68) }
                                personRow(id: m.userId, email: m.invitedEmail,
                                          sub: m.status != "active" ? "семья · ещё не приняла приглашение" : (m.userId.map(existing.contains) == true ? "уже видит место" : "семья"),
                                          has: m.userId.map(existing.contains) == true)
                            }
                        }
                    }
                    if !recentRows.isEmpty {
                        SectionTitle("Недавно делились")
                        SettingsCard {
                            ForEach(Array(recentRows.enumerated()), id: \.element) { i, u in
                                if i > 0 { Divider().padding(.leading, 68) }
                                personRow(id: u, email: nil, sub: existing.contains(u) ? "уже видит место" : "делились раньше", has: existing.contains(u))
                            }
                        }
                    }
                    SectionTitle("Из контактов iPhone")
                    SettingsCard {
                        Button { contacts = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40).background(Theme.fill, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Выбрать из контактов").font(.system(size: 16, weight: .semibold))
                                    Text("Возьмём только email выбранных — доступ ко всей книге не нужен").font(.footnote).foregroundStyle(Theme.muted)
                                }
                                Spacer(); Chevron()
                            }
                            .padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if !q.isEmpty && familyRows.isEmpty && recentRows.isEmpty && !isEmail {
                        Text("Никого не нашли. Введите email полностью — пригласим письмом.").font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(16).padding(.bottom, 140)
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Кого добавить").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Готово" : "Готово · \(picked.count)") { Task { await commit() } }.disabled(picked.isEmpty || busy).fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty {
                    VStack(spacing: 10) {
                        Text(summary).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                        Picker("", selection: $role) { Text("Смотрят").tag("view"); Text("Редактируют").tag("edit") }.pickerStyle(.segmented)
                        Button { Task { await commit() } } label: {
                            if busy { ProgressView().tint(Theme.onInk) } else { Text("Добавить \(picked.count.people) · \(role == "edit" ? "редактируют" : "смотрят")") }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    }
                    .padding(16).background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: picked.isEmpty)
            .sheet(isPresented: $contacts) {
                ContactsPicker { emails in for e in emails { toggle(.email(e.lowercased()), forceOn: true) } }.ignoresSafeArea()
            }
            .task { if !access.loaded { await access.loadFamily() } }
        }
    }

    private var summary: String {
        let names = picked.map { p -> String in
            switch p { case .user(let u): access.person(u)?.name ?? "…"; case .email(let e): e }
        }
        return names.count == 1 ? names[0] : names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " и ещё \(names.count - 2)" : "")
    }

    private func matches(_ m: FamilyMember) -> Bool { q.isEmpty || access.name(m).localizedCaseInsensitiveContains(q) || (m.invitedEmail ?? "").localizedCaseInsensitiveContains(q) }
    private func matches(_ u: UUID) -> Bool { q.isEmpty || (access.person(u)?.name ?? "").localizedCaseInsensitiveContains(q) }

    private func personRow(id: UUID?, email: String?, sub: String, has: Bool) -> some View {
        let pick: Pick? = id.map(Pick.user) ?? email.map { Pick.email($0.lowercased()) }
        let on = pick.map(picked.contains) ?? false
        return Button { if let pick, !has { toggle(pick) } } label: {
            HStack(spacing: 12) {
                PersonAvatar(person: access.person(id), fallback: String((email ?? "?").prefix(1)).uppercased())
                VStack(alignment: .leading, spacing: 2) {
                    Text(access.person(id)?.name ?? email ?? "—").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(sub).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: has ? "checkmark" : on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(has ? Theme.line : on ? Theme.accent : Theme.line)
            }
            .padding(12).contentShape(Rectangle()).opacity(has ? 0.5 : 1)
        }
        .buttonStyle(.plain).disabled(has)
    }

    private func toggle(_ p: Pick, forceOn: Bool = false) {
        withAnimation(.snappy) {
            if let i = picked.firstIndex(of: p) { if !forceOn { picked.remove(at: i) } } else { picked.append(p) }
        }
    }

    private func commit() async {
        busy = true; defer { busy = false }; error = nil
        var added = 0
        for p in picked {
            do {
                switch p {
                case .user(let u): try await access.grantPlace(placeId, userId: u, role: role); added += 1
                case .email(let e): _ = try await access.invite(email: e, kind: "place", placeId: placeId, role: role); added += 1
                }
            } catch { self.error = "Не получилось добавить \(p.id): \(error.localizedDescription)" }
        }
        if error == nil { dismiss(); onDone(added) } else { onDone(added) }
    }
}

/// Системный выбор контактов: Box Nº получит только email выбранных; разрешение на всю книгу не запрашивается.
struct ContactsPicker: UIViewControllerRepresentable {
    let onPick: ([String]) -> Void
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let p = CNContactPickerViewController()
        p.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        p.predicateForSelectionOfContact = NSPredicate(value: true)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        init(_ onPick: @escaping ([String]) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts.compactMap { $0.emailAddresses.first.map { String($0.value) } })
        }
    }
}
