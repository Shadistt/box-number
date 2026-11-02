import SwiftUI
import Supabase
import Observation

/// Кто видит: семья, доступ к переезду, доступ к месту, ссылка на место. Таблицы: families / family_members /
/// move_access / place_access / place_shares (RLS: владелец управляет, участники читают).
struct FamilyMember: Codable, Identifiable, Hashable {
    var id: UUID
    var familyId: UUID
    var userId: UUID?
    var invitedEmail: String?
    var status: String        // invited | active
    var role: String          // view | edit
    var createdAt: Date
    enum CodingKeys: String, CodingKey { case id, status, role, familyId = "family_id", userId = "user_id", invitedEmail = "invited_email", createdAt = "created_at" }
}

struct AccessRow: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID?
    var invitedEmail: String?
    var role: String
    var status: String
    var lastOpenedAt: Date?
    var createdAt: Date
    enum CodingKeys: String, CodingKey { case id, role, status, userId = "user_id", invitedEmail = "invited_email", lastOpenedAt = "last_opened_at", createdAt = "created_at" }
}

struct PlaceShare: Codable, Hashable {
    var placeId: UUID
    var linkEnabled: Bool
    var linkCode: String?
    var linkRole: String
    var passwordEnabled: Bool
    enum CodingKeys: String, CodingKey { case placeId = "place_id", linkEnabled = "link_enabled", linkCode = "link_code", linkRole = "link_role", passwordEnabled = "password_enabled" }
    var url: URL? { linkCode.map { URL(string: "https://boxnumber.co/b/\($0)")! } }
}

/// Короткий профиль для списков доступа.
struct Person: Codable, Identifiable, Hashable {
    var id: UUID
    var firstName: String
    var lastName: String
    var email: String?
    var avatar: String
    var photo: String?
    enum CodingKeys: String, CodingKey { case id, email, avatar, photo, firstName = "first_name", lastName = "last_name" }
    static let columns = "id,first_name,last_name,email,avatar,photo"
    var name: String { let n = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " "); return n.isEmpty ? (email ?? "Без имени") : n }
    var initial: String { String(name.prefix(1)).uppercased() }
}

@MainActor
@Observable
final class AccessStore {
    static let shared = AccessStore()

    var familyId: UUID?
    var family: [FamilyMember] = []
    var people: [UUID: Person] = [:]
    var recent: [UUID] = []
    var familyAutoShare = true
    var familyAutoRole = "edit"
    var loaded = false

    var me: UUID? { supabase.auth.currentUser?.id }
    func person(_ id: UUID?) -> Person? { id.flatMap { people[$0] } }
    func name(_ row: AccessRow) -> String { person(row.userId)?.name ?? row.invitedEmail ?? "—" }
    func name(_ m: FamilyMember) -> String { person(m.userId)?.name ?? m.invitedEmail ?? "—" }
    /// Семья без меня (для списков «кому открыть»).
    var others: [FamilyMember] { family.filter { $0.userId != me } }

    // MARK: семья

    func loadFamily() async {
        do {
            let fid: UUID = try await supabase.rpc("my_family").execute().value
            familyId = fid
            struct Fam: Decodable { let auto_share: Bool; let auto_role: String }
            if let f: Fam = try? await supabase.from("families").select("auto_share,auto_role").eq("id", value: fid).single().execute().value {
                familyAutoShare = f.auto_share; familyAutoRole = f.auto_role
            }
            family = try await supabase.from("family_members").select().eq("family_id", value: fid).order("created_at").execute().value
            await loadPeople(family.compactMap(\.userId))
            if let r: [RecentRow] = try? await supabase.rpc("recent_shares").execute().value {
                recent = r.map(\.userId); await loadPeople(recent)
            }
            loaded = true
        } catch { print("family:", error) }
    }
    private struct RecentRow: Decodable { let userId: UUID; enum CodingKeys: String, CodingKey { case userId = "user_id" } }

    func loadPeople(_ ids: [UUID]) async {
        let missing = Set(ids).subtracting(people.keys)
        guard !missing.isEmpty else { return }
        do {
            let rows: [Person] = try await supabase.from("profiles").select(Person.columns).in("id", values: Array(missing).map(\.uuidString)).execute().value
            for p in rows { people[p.id] = p }
        } catch { print("people:", error) }
    }

    func setFamilyAuto(share: Bool? = nil, role: String? = nil) async {
        guard let familyId else { return }
        if let share { familyAutoShare = share }
        if let role { familyAutoRole = role }
        do { try await supabase.from("families").update(["auto_share": AnyJSON.bool(familyAutoShare), "auto_role": .string(familyAutoRole)]).eq("id", value: familyId).execute() }
        catch { print("family auto:", error) }
    }

    func removeFromFamily(_ m: FamilyMember) async {
        do { try await supabase.from("family_members").delete().eq("id", value: m.id).execute(); family.removeAll { $0.id == m.id } }
        catch { print("family remove:", error) }
    }

    // MARK: приглашения (Edge Function send-invite: строка доступа + письмо)

    struct InviteResult: Decodable { let ok: Bool; let existing: Bool }
    func invite(email: String, kind: String, moveId: UUID? = nil, placeId: UUID? = nil, role: String = "view") async throws -> InviteResult {
        struct Body: Encodable { var email: String; var kind: String; var move_id: UUID?; var place_id: UUID?; var role: String }
        return try await supabase.functions.invoke("send-invite", options: .init(body: Body(email: email, kind: kind, move_id: moveId, place_id: placeId, role: role)))
    }

    // MARK: доступ к переезду (§9)

    /// Последний загруженный список доступа по переезду — экран «Кто видит переезд» открывается сразу с ним,
    /// а не с выключенными переключателями до ответа сервера.
    var moveAccessCache: [UUID: [AccessRow]] = [:]

    func moveAccess(_ moveId: UUID) async -> [AccessRow] {
        do {
            let rows: [AccessRow] = try await supabase.from("move_access").select("id,user_id,invited_email,role,status,created_at")
                .eq("move_id", value: moveId).execute().value
            moveAccessCache[moveId] = rows
            await loadPeople(rows.compactMap(\.userId)); return rows
        } catch { print("move access:", error); return moveAccessCache[moveId] ?? [] }
    }
    func grantMove(_ moveId: UUID, userId: UUID, role: String) async throws {
        struct Row: Encodable { var move_id: UUID; var user_id: UUID; var role: String; var status = "active"; var granted_by: UUID? }
        try await supabase.from("move_access").upsert(Row(move_id: moveId, user_id: userId, role: role, granted_by: me), onConflict: "move_id,user_id").execute()
    }
    func revoke(table: String, id: UUID) async throws {
        try await supabase.from(table).delete().eq("id", value: id).execute()
    }
    func setRole(table: String, id: UUID, role: String) async throws {
        try await supabase.from(table).update(["role": role]).eq("id", value: id).execute()
    }

    // MARK: доступ к месту (§8)

    func placeAccess(_ placeId: UUID) async -> [AccessRow] {
        do {
            let rows: [AccessRow] = try await supabase.from("place_access").select("id,user_id,invited_email,role,status,last_opened_at,created_at")
                .eq("place_id", value: placeId).execute().value
            await loadPeople(rows.compactMap(\.userId)); return rows
        } catch { print("place access:", error); return [] }
    }
    func grantPlace(_ placeId: UUID, userId: UUID, role: String) async throws {
        struct Row: Encodable { var place_id: UUID; var user_id: UUID; var role: String; var status = "active"; var granted_by: UUID? }
        try await supabase.from("place_access").upsert(Row(place_id: placeId, user_id: userId, role: role, granted_by: me), onConflict: "place_id,user_id").execute()
        try await supabase.from("places").update(["shared": true]).eq("id", value: placeId).execute()
    }

    func placeShare(_ placeId: UUID) async -> PlaceShare? {
        try? await supabase.from("place_shares").select("place_id,link_enabled,link_code,link_role,password_enabled").eq("place_id", value: placeId).maybeSingle().execute().value
    }
    /// Ссылка: включить/выключить, роль, пароль (nil — без пароля; строка — новый пароль).
    func setPlaceLink(_ placeId: UUID, enabled: Bool, role: String, password: String?) async throws -> PlaceShare {
        struct P: Encodable { var p_place: UUID; var p_enabled: Bool; var p_role: String; var p_password: String? }
        return try await supabase.rpc("set_place_link", params: P(p_place: placeId, p_enabled: enabled, p_role: role, p_password: password)).execute().value
    }

    // MARK: ссылка-приглашение (получатель)

    struct SharedPlace: Decodable, Identifiable, Hashable {
        var id: UUID { placeId }
        let placeId: UUID, moveId: UUID, number: String, title: String, kind: PlaceKind, items: Int, role: String, ownerName: String?
        enum CodingKeys: String, CodingKey { case number, title, kind, items, role, placeId = "place_id", moveId = "move_id", ownerName = "owner_name" }
    }
    func openShareLink(code: String, password: String?) async throws -> SharedPlace {
        struct P: Encodable { var p_code: String; var p_password: String? }
        let rows: [SharedPlace] = try await supabase.rpc("open_share_link", params: P(p_code: code, p_password: password)).execute().value
        guard let r = rows.first else { throw URLError(.resourceUnavailable) }
        return r
    }

    /// После входа: приглашения по моему email становятся доступом.
    // MARK: приглашения мне (pending) и блокировки

    /// Приглашение мне. state: pending | accepted | declined | expired | blocked; kind: family | move | place | block.
    struct Invitation: Decodable, Identifiable, Hashable {
        var kind: String
        var id: UUID
        var inviterId: UUID?
        var inviterName: String
        var inviterEmail: String
        var title: String?
        var role: String?
        var createdAt: Date
        var state: String
        var daysLeft: Int?
        enum CodingKeys: String, CodingKey { case kind, id, title, role, state
            case inviterId = "inviter_id", inviterName = "inviter_name", inviterEmail = "inviter_email", createdAt = "created_at", daysLeft = "days_left" }
        var text: String {
            switch kind {
            case "family": "приглашает вас в семью"
            case "move": "приглашает вас в переезд «\(title ?? "")» и в семью"
            case "place": "открывает вам место \(title ?? "")"
            default: ""
            }
        }
        /// «в переезд «Вена → Киев»» — для строки в разделе «Приглашения».
        var what: String {
            switch kind {
            case "family": "в семью"
            case "move": "в переезд «\(title ?? "")»"
            case "place": "место \(title ?? "")"
            default: "заблокирован(а)"
            }
        }
        var roleText: String { role == "edit" ? "можно редактировать" : "только смотреть" }
    }
    struct Block: Decodable, Identifiable, Hashable {
        var id: UUID; var email: String; var name: String?; var createdAt: Date
        enum CodingKeys: String, CodingKey { case id, email, name, createdAt = "created_at" }
    }
    /// Все приглашения мне (раздел «Приглашения»); на главном — только ждущие.
    var allInvitations: [Invitation] = []
    var invitations: [Invitation] { allInvitations.filter { $0.state == "pending" } }
    var blocks: [Block] = []

    func loadInvitations() async {
        do { allInvitations = try await supabase.rpc("my_invitations").execute().value } catch { print("my_invitations:", error) }
    }
    private struct KindId: Encodable { var p_kind: String; var p_id: UUID }

    /// Принять / отклонить. Переезд и семья от одного человека — один ответ на оба (ТЗ §9).
    /// Отказ тихий: отправитель продолжает видеть «ждём ответа». Принять можно и отклонённое — в течение 30 дней.
    func respond(_ inv: Invitation, accept: Bool) async throws {
        struct P: Encodable { var p_kind: String; var p_id: UUID; var p_accept: Bool }
        try await supabase.rpc("respond_invitation", params: P(p_kind: inv.kind, p_id: inv.id, p_accept: accept)).execute()
        if accept { MovesStore.clearCache() }
        await loadInvitations()
    }
    /// «Отменить» сразу после отказа: приглашение снова ждёт ответа.
    func undoDecline(_ inv: Invitation) async throws {
        try await supabase.rpc("undo_decline", params: KindId(p_kind: inv.kind, p_id: inv.id)).execute()
        await loadInvitations()
    }
    /// «Выйти» из принятого: доступ закрывается.
    func leave(_ inv: Invitation) async throws {
        try await supabase.rpc("leave_access", params: KindId(p_kind: inv.kind, p_id: inv.id)).execute()
        MovesStore.clearCache()
        await loadInvitations()
    }
    /// «Пригласить снова» у отправителя — для истёкшего приглашения (старше 30 дней).
    func reinvite(kind: String, id: UUID) async throws {
        try await supabase.rpc("reinvite", params: KindId(p_kind: kind, p_id: id)).execute()
    }
    /// Заблокировать: его приглашения больше не доходят; он об этом не узнаёт.
    @discardableResult
    func block(email: String) async throws -> UUID {
        let id: UUID = try await supabase.rpc("block_user", params: ["p_email": email]).execute().value
        await loadBlocks(); await loadInvitations()
        return id
    }
    func unblock(_ id: UUID) async throws {
        try await supabase.from("blocks").delete().eq("id", value: id).execute()
        blocks.removeAll { $0.id == id }
        await loadInvitations()
    }
    /// Разблокировать по email (из строки приглашения со статусом «Заблокирован»).
    func unblock(email: String) async throws {
        await loadBlocks()
        if let b = blocks.first(where: { $0.email.lowercased() == email.lowercased() }) { try await unblock(b.id) }
    }
    func loadBlocks() async {
        do { blocks = try await supabase.rpc("my_blocks").execute().value } catch { print("my_blocks:", error) }
    }

    func claimInvites() async {
        do { let n: Int = try await supabase.rpc("claim_invites").execute().value; if n > 0 { MovesStore.clearCache() } }
        catch { print("claim_invites:", error) }
    }

    func clear() { familyId = nil; family = []; people = [:]; recent = []; allInvitations = []; blocks = []; loaded = false }
}

/// Кружок с инициалом или фото — для списков людей.
struct PersonAvatar: View {
    let person: Person?
    var fallback: String = "?"
    var size: CGFloat = 40
    @State private var image: UIImage? = nil
    private static let colors: [Color] = [Theme.accent, Color(hex: 0x3B4D74), Color(hex: 0x4D5F4A), Color(hex: 0x8C6BB1), Color(hex: 0xC9A27A)]

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                let seed = person?.id.uuidString.first.map { Int($0.asciiValue ?? 0) } ?? 0
                (person == nil ? Theme.fill : Self.colors[seed % Self.colors.count])
                Text(person?.initial ?? fallback).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(person == nil ? Theme.muted : .white)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: person?.photo) {
            guard let p = person, let key = p.photo else { image = nil; return }
            struct Ticket: Decodable { let url: String }
            if let t: Ticket = try? await supabase.functions.invoke("avatar-url", options: .init(body: ["op": "get", "key": key])),
               let (d, _) = try? await URLSession.shared.data(from: URL(string: t.url)!) { image = UIImage(data: d) }
        }
    }
}

extension String {
    /// Похоже на email: имя@домен.зона, без пробелов (а не просто «есть @ и точка»).
    var isValidEmail: Bool {
        range(of: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }
}

/// Приглашение, отправленное мной, не принятое за 30 дней — «истекло» (отказ и блокировку отправитель не видит).
extension Date { var inviteExpired: Bool { Date().timeIntervalSince(self) > 30 * 86_400 } }

extension Int {
    /// «1 человек / 2 человека / 5 человек»
    var people: String { "\(self) " + Plural.form(self, "человек", "человека", "человек") }
    /// «1 место / 2 места / 5 мест»
    var placesWord: String { "\(self) " + Plural.form(self, "место", "места", "мест") }
}
