import SwiftUI

/// Настройки → Семья (макет Family): участники, приглашение, автодоступ к новым местам, убрать из семьи.
struct FamilyView: View {
    @State private var access = AccessStore.shared
    @State private var invite = false
    @State private var confirmRemove: FamilyMember? = nil
    @State private var toast: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Люди, которым вы делитесь одним касанием. У каждого свой аккаунт и свои лимиты.")
                    .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)

                SectionTitle("Участники · \(access.family.count)")
                SettingsCard {
                    ForEach(Array(access.family.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Divider().padding(.leading, 68) }
                        let isMe = m.userId == access.me
                        HStack(spacing: 12) {
                            PersonAvatar(person: access.person(m.userId), fallback: isMe ? "Я" : String((m.invitedEmail ?? "?").prefix(1)).uppercased())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isMe ? "Вы" : access.name(m)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                Text(isMe ? (access.person(m.userId)?.email ?? "") : m.status == "invited" ? "приглашение отправлено \(m.createdAt.formatted(.relative(presentation: .named)))" : "в семье с \(m.createdAt.formatted(.dateTime.day().month()))")
                                    .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            if !isMe {
                                if m.status == "invited" {
                                    Button("Напомнить") { Task { await remind(m) } }.font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 10).frame(height: 30).background(Theme.fill, in: Capsule()).foregroundStyle(Theme.ink)
                                }
                                Button { confirmRemove = m } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 30, height: 30) }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
                Button { invite = true } label: { Label("Пригласить в семью", systemImage: "person.badge.plus") }.buttonStyle(PrimaryButtonStyle())

                SectionTitle("Автоматически")
                SettingsCard {
                    Toggle(isOn: Binding(get: { access.familyAutoShare }, set: { v in Task { await access.setFamilyAuto(share: v) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Семья видит все места переезда").font(.system(size: 16, weight: .semibold))
                            Text("Новые места открываются семье сами").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }.tint(Theme.accent).padding(16)
                    Divider().padding(.leading, 16)
                    HStack {
                        Text("Роль для новых мест").font(.system(size: 16))
                        Spacer()
                        Picker("", selection: Binding(get: { access.familyAutoRole }, set: { v in Task { await access.setFamilyAuto(role: v) } })) {
                            Text("Смотрит").tag("view"); Text("Редактирует").tag("edit")
                        }.pickerStyle(.segmented).frame(width: 200)
                    }.padding(16)
                }
                Text("Семья — это не общий аккаунт: у каждого свои переезды. Общие места считаются в лимит того, кто их создал.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Семья").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Убрать \(confirmRemove.map(access.name) ?? "") из семьи?", isPresented: .init(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Убрать из семьи", role: .destructive) { if let m = confirmRemove { Task { await access.removeFromFamily(m); flash("\(access.name(m)) больше не в семье") } } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Потеряет доступ к общим местам и перестанет видеть новые. Собственные места останутся.") }
        .sheet(isPresented: $invite) { InviteFamilyView { n in Task { await access.loadFamily() }; if n > 0 { flash(n == 1 ? "Приглашение отправлено" : "Отправлено приглашений: \(n)") } } }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 18).frame(height: 48).background(Theme.ink, in: Capsule()).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
        .task { await access.loadFamily() }
    }

    private func remind(_ m: FamilyMember) async {
        guard let e = m.invitedEmail else { return }
        do { _ = try await access.invite(email: e, kind: "family"); flash("Напомнили на \(e)") } catch { flash("Не получилось") }
    }
    private func flash(_ t: String) { toast = t; Task { try? await Task.sleep(for: .seconds(2.5)); if toast == t { toast = nil } } }
}

/// Пригласить в семью (макет InviteFamily): email или контакты iPhone; несколько адресов — чипами.
struct InviteFamilyView: View {
    let onDone: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var email = ""
    @State private var emails: [String] = []
    @State private var contacts = false
    @State private var busy = false
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    private var valid: Bool { let e = email.trimmingCharacters(in: .whitespaces); return e.contains("@") && e.contains(".") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Приглашённый получит письмо; после входа в Box Nº с этим адресом окажется в вашей семье.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    SectionTitle("Кому")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if !emails.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(emails, id: \.self) { e in
                                        HStack(spacing: 6) {
                                            Text(e).font(.footnote.weight(.semibold))
                                            Button { emails.removeAll { $0 == e } } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                        }
                                        .padding(.horizontal, 10).frame(height: 28).background(Theme.fill, in: Capsule()).foregroundStyle(Theme.ink)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                TextField(emails.isEmpty ? "Email" : "Добавить ещё", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).submitLabel(.done)
                                    .onSubmit { addEmail() }.fieldStyle()
                                Button { contacts = true } label: {
                                    Image(systemName: "book.closed").font(.system(size: 18, weight: .semibold))
                                        .frame(width: 52, height: 52).background(Theme.fill, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.ink)
                                }
                            }
                            Text("Введите email или нажмите книжку и выберите из контактов iPhone — возьмём email контакта. Мы увидим только выбранных, доступ ко всему справочнику не нужен.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { Task { await send() } } label: {
                        if busy { ProgressView().tint(Theme.onInk) } else { Text(total == 0 ? "Отправить приглашение" : "Отправить приглашение · \(total)") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(total == 0 || busy).opacity(total == 0 ? 0.5 : 1)
                    ShareLink(item: URL(string: "https://boxnumber.co")!, message: Text("Присоединяйся к моей семье в Box Nº — коробки с номером маркером и фото всего, что внутри.")) {
                        Label("Поделиться ссылкой-приглашением", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: Theme.ink))
                    Text("Telegram, WhatsApp…").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(Theme.bg).scrollDismissesKeyboard(.interactively)
            .navigationTitle("Пригласить в семью").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .sheet(isPresented: $contacts) { ContactsPicker { es in for e in es where !emails.contains(e.lowercased()) { emails.append(e.lowercased()) } }.ignoresSafeArea() }
            .task { focused = true }
        }
    }

    private var total: Int { emails.count + (valid ? 1 : 0) }
    private func addEmail() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard valid, !emails.contains(e) else { return }
        emails.append(e); email = ""
    }
    private func send() async {
        addEmail()
        busy = true; defer { busy = false }; error = nil
        var n = 0
        for e in emails {
            do { _ = try await access.invite(email: e, kind: "family"); n += 1 }
            catch { self.error = "\(e): \(error.localizedDescription)" }
        }
        if error == nil { dismiss() }
        onDone(n)
    }
}
