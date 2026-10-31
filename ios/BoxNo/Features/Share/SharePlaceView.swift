import SwiftUI
import Supabase

/// §8 «Поделиться местом» (макет ShareBox): ссылка (вкл/выкл, роль, пароль 6 цифр), «Есть доступ · N», «Добавить людей».
struct SharePlaceView: View {
    let store: PlacesStore
    let placeId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var access = AccessStore.shared
    @State private var share: PlaceShare? = nil
    @State private var rows: [AccessRow] = []
    @State private var viaMove: [AccessRow] = []    // видят через доступ ко всему переезду — показываем серым, без правки
    @State private var password: String? = nil      // показываем только что заданный пароль; старый не восстановить
    @State private var busy = false
    @State private var toast: String? = nil
    @State private var addPeople = false
    @State private var confirmRemove: AccessRow? = nil

    private var place: Place? { store.place(placeId) }
    private var linkOn: Bool { share?.linkEnabled ?? false }
    private var linkRole: String { share?.linkRole ?? "view" }
    private var pwdOn: Bool { share?.passwordEnabled ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let place {
                        HStack(spacing: 12) {
                            BoxTileView(place: place, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(place.kind.numberLabel) № \(place.number)").font(.system(size: 18, weight: .heavy))
                                Text("\(place.displayTitle) · \(Plural.things(store.items(of: placeId).count))").font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    SectionTitle("Ссылка")
                    SettingsCard {
                        Toggle(isOn: Binding(get: { linkOn }, set: { on in Task { await setLink(enabled: on) } })) {
                            Text("Доступ по ссылке").font(.system(size: 17, weight: .semibold))
                        }
                        .tint(Theme.accent).padding(16)
                        if linkOn {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("По ссылке можно").font(.system(size: 15))
                                Spacer()
                                Picker("", selection: Binding(get: { linkRole }, set: { r in Task { await setLink(role: r) } })) {
                                    Text("Смотреть").tag("view"); Text("Редактировать").tag("edit")
                                }.pickerStyle(.segmented).frame(width: 220)
                            }
                            .padding(16)
                            Divider().padding(.leading, 16)
                            Toggle(isOn: Binding(get: { pwdOn }, set: { on in Task { await setPassword(on) } })) {
                                Text("Пароль на ссылку · 6 цифр").font(.system(size: 15))
                            }
                            .tint(Theme.accent).padding(16)
                            if pwdOn {
                                HStack(spacing: 10) {
                                    Text(password.map { String($0.prefix(3)) + " " + String($0.suffix(3)) } ?? "••• •••")
                                        .font(.system(size: 26, weight: .heavy, design: .monospaced)).tracking(2)
                                    Spacer()
                                    if let password {
                                        Button { UIPasteboard.general.string = password; flash("Пароль скопирован") } label: { Image(systemName: "doc.on.doc") }
                                    }
                                    Button { Task { await setPassword(true, regenerate: true) } } label: { Image(systemName: "arrow.clockwise") }
                                }
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16).padding(.bottom, 6)
                                Text(password == nil ? "Пароль задан. Чтобы увидеть новый — сгенерируйте заново." : "Сообщите получателю отдельно от ссылки.")
                                    .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 14)
                            }
                            Divider().padding(.leading, 16)
                            if let url = share?.url {
                                HStack(spacing: 12) {
                                    Text(url.absoluteString.replacingOccurrences(of: "https://", with: "")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Button { UIPasteboard.general.string = url.absoluteString; flash("Ссылка скопирована") } label: { Image(systemName: "doc.on.doc") }
                                    ShareLink(item: url, subject: Text("Коробка в Box Nº"), message: Text(shareMessage)) { Image(systemName: "square.and.arrow.up") }
                                }
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
                                .padding(16)
                            }
                        } else {
                            Text("Ссылка выключена. Те, у кого она уже есть, больше не откроют место.")
                                .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 14)
                        }
                    }

                    SectionTitle("Есть доступ · \((rows.count + viaMove.count + 1).people)")
                    SettingsCard {
                        HStack(spacing: 12) {
                            PersonAvatar(person: access.person(access.me), fallback: "Я")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Вы").font(.system(size: 16, weight: .semibold))
                                Text("Вы владелец").font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .padding(16)
                        ForEach(rows) { r in
                            Divider().padding(.leading, 68)
                            HStack(spacing: 12) {
                                PersonAvatar(person: access.person(r.userId), fallback: String((r.invitedEmail ?? "?").prefix(1)).uppercased())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(access.name(r)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                    Text(sub(r)).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Button(r.role == "edit" ? "Редактирует" : "Смотрит") { Task { await toggleRole(r) } }
                                    .font(.footnote.weight(.semibold)).padding(.horizontal, 10).frame(height: 30)
                                    .background(Theme.fill, in: Capsule()).foregroundStyle(Theme.ink)
                                Button { confirmRemove = r } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 30, height: 30) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        // Доступ через переезд: закрыть или сменить роль здесь нельзя — это делается в «Кто видит переезд».
                        ForEach(viaMove.filter { m in !rows.contains { $0.userId == m.userId } }) { r in
                            Divider().padding(.leading, 68)
                            HStack(spacing: 12) {
                                PersonAvatar(person: access.person(r.userId), fallback: String((r.invitedEmail ?? "?").prefix(1)).uppercased())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(access.name(r)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                                    Text(r.status == "invited" ? "видит через переезд · ждём ответа" : "видит через переезд").font(.footnote).lineLimit(1)
                                }
                                Spacer()
                                Text(r.role == "edit" ? "Редактирует" : "Смотрит").font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10).frame(height: 30).background(Theme.fill.opacity(0.6), in: Capsule())
                            }
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }
                    if !viaMove.isEmpty {
                        Text("Серым — те, кто видит всё в переезде. Их доступ настраивается в меню переезда → «Кто видит переезд».")
                            .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                    Button { addPeople = true } label: { Label("Добавить людей", systemImage: "person.badge.plus") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Поделиться").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onInk)
                        .padding(.horizontal, 18).frame(height: 48).background(Theme.ink, in: Capsule()).padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: toast)
            .overlay { if busy { ProgressView() } }
            .confirmationDialog("Закрыть доступ для \(confirmRemove.map(access.name) ?? "")?", isPresented: .init(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
                Button("Закрыть доступ", role: .destructive) { if let r = confirmRemove { Task { await remove(r) } } }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(isPresented: $addPeople) {
                SharePeopleView(placeId: placeId, placeTitle: place.map { "\($0.kind.numberLabel) № \($0.number) · \($0.displayTitle)" } ?? "", existing: rows.compactMap(\.userId)) { added in
                    Task { rows = await access.placeAccess(placeId) }
                    if added > 0 { flash(added == 1 ? "1 человек теперь видит место" : "\(added.people) теперь видят место") }
                }
            }
            .task {
                await access.loadFamily()
                share = await access.placeShare(placeId)
                rows = await access.placeAccess(placeId)
                viaMove = await access.moveAccess(store.move.id)
            }
        }
    }

    private var shareMessage: String {
        guard let place else { return "" }
        return "\(place.kind.numberLabel) № \(place.number) «\(place.displayTitle)» в Box Nº" + (pwdOn ? ". Пароль пришлю отдельно." : "")
    }

    private func sub(_ r: AccessRow) -> String {
        if r.status == "invited" { return "приглашение отправлено · ждём" }
        let fam = access.family.contains { $0.userId == r.userId } ? "из семьи · " : ""
        if let at = r.lastOpenedAt { return fam + "открывал " + at.formatted(.relative(presentation: .named)) }
        return fam + "ещё не открывал"
    }

    private func setLink(enabled: Bool? = nil, role: String? = nil) async {
        busy = true; defer { busy = false }
        do {
            share = try await access.setPlaceLink(placeId, enabled: enabled ?? linkOn, role: role ?? linkRole, password: pwdOn ? nil : nil)
            if enabled == false { password = nil }
        } catch { flash("Не получилось: \(error.localizedDescription)") }
    }

    private func setPassword(_ on: Bool, regenerate: Bool = false) async {
        busy = true; defer { busy = false }
        do {
            if on {
                let code = String(format: "%06d", Int.random(in: 0...999_999))
                share = try await access.setPlaceLink(placeId, enabled: true, role: linkRole, password: code)
                password = code
                if regenerate { flash("Новый пароль. Старый больше не подходит") }
            } else {
                // Выключить пароль: пересоздаём настройки без пароля через отдельный вызов (password_enabled = false).
                try await supabase.from("place_shares").update(["password_enabled": AnyJSON.bool(false), "password_hash": .null]).eq("place_id", value: placeId).execute()
                share = await access.placeShare(placeId); password = nil
            }
        } catch { flash("Не получилось: \(error.localizedDescription)") }
    }

    private func toggleRole(_ r: AccessRow) async {
        let new = r.role == "edit" ? "view" : "edit"
        do { try await access.setRole(table: "place_access", id: r.id, role: new); rows = await access.placeAccess(placeId) }
        catch { flash("Не получилось") }
    }
    private func remove(_ r: AccessRow) async {
        do { try await access.revoke(table: "place_access", id: r.id); rows.removeAll { $0.id == r.id }; flash("\(access.name(r)) больше не видит место") }
        catch { flash("Не получилось") }
    }
    private func flash(_ t: String) { toast = t; Task { try? await Task.sleep(for: .seconds(2.5)); if toast == t { toast = nil } } }
}
