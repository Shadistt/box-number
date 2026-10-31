import SwiftUI
import Supabase
import Observation

/// Профиль пользователя (таблица profiles) + способы входа + сводка «мест · фото».
struct Profile: Codable, Hashable {
    var id: UUID
    var firstName: String
    var lastName: String
    var email: String
    var avatar: String          // "preset:<name>" или "photo" (своё фото)
    var photo: String?          // ключ R2 "avatars/<uid>.jpg", остаётся и при выбранном пресете
    var locale: String
    var twoFactor: Bool
    var twoFactorVerifiedAt: Date?
    enum CodingKeys: String, CodingKey {
        case id, email, avatar, photo, locale
        case firstName = "first_name", lastName = "last_name"
        case twoFactor = "two_factor", twoFactorVerifiedAt = "two_factor_verified_at"
    }
    static let columns = "id,first_name,last_name,email,avatar,photo,locale,two_factor,two_factor_verified_at"

    var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var hasCustomAvatar: Bool { avatar == "photo" && photo != nil }
    /// Двухфакторная проверка нужна, если включена и последняя была больше 30 дней назад.
    var needsTwoFactorCheck: Bool {
        guard twoFactor else { return false }
        guard let at = twoFactorVerifiedAt else { return true }
        return Date().timeIntervalSince(at) > 30 * 86_400
    }
}

struct Usage: Decodable {
    var places: Int
    var photos: Int
    var syncedAt: Date?
    enum CodingKeys: String, CodingKey { case places, photos, syncedAt = "synced_at" }
}

@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    var profile: Profile?
    var usage: Usage?
    var identities: [UserIdentity] = []
    var hasPassword = false
    var avatarImage: UIImage?
    var loaded = false

    private static let avatarFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("avatar.jpg")

    // MARK: загрузка

    func load() async {
        guard let uid = supabase.auth.currentUser?.id else { return }
        do {
            let p: Profile = try await supabase.from("profiles").select(Profile.columns).eq("id", value: uid).single().execute().value
            profile = p
            loaded = true
            if let key = p.photo, avatarImage == nil {
                if let img = UIImage(contentsOfFile: Self.avatarFile.path) { avatarImage = img } else { await fetchAvatar(key: key) }
            } else if p.photo == nil { avatarImage = nil }
        } catch { print("profile load:", error) }
        await loadUsage()
        await loadIdentities()
    }

    func loadUsage() async {
        do { let u: Usage = try await supabase.rpc("my_usage").execute().value; usage = u } catch { print("my_usage:", error) }
    }

    func loadIdentities() async {
        do {
            identities = try await supabase.auth.userIdentities()
            // Пароль «задан», если есть identity email: Supabase создаёт её при регистрации по паролю
            // или при первом update(password:). Для входа только через Apple/Google её нет.
            hasPassword = identities.contains { $0.provider == "email" }
        } catch { print("identities:", error) }
    }

    func identity(_ provider: String) -> UserIdentity? { identities.first { $0.provider == provider } }
    func identityEmail(_ provider: String) -> String? {
        guard case .string(let e)? = identity(provider)?.identityData?["email"] else { return nil }
        return e
    }
    /// Нельзя отвязать последний способ входа.
    var canUnlinkProvider: Bool { identities.count > 1 }

    // MARK: правки

    func update(firstName: String? = nil, lastName: String? = nil, locale: String? = nil) async {
        guard var p = profile else { return }
        if let firstName { p.firstName = firstName }
        if let lastName { p.lastName = lastName }
        if let locale { p.locale = locale }
        profile = p
        struct Patch: Encodable { var first_name: String; var last_name: String; var locale: String }
        do {
            try await supabase.from("profiles").update(Patch(first_name: p.firstName, last_name: p.lastName, locale: p.locale)).eq("id", value: p.id).execute()
        } catch { print("profile update:", error) }
    }

    /// Выбрать аватарку: пресет или "photo" (своё фото остаётся в карусели, пока его не удалили).
    func setAvatar(_ value: String) async {
        guard var p = profile, p.avatar != value else { return }
        p.avatar = value; profile = p
        do { try await supabase.from("profiles").update(["avatar": value]).eq("id", value: p.id).execute() } catch { print("avatar:", error) }
    }
    func setPreset(_ name: String) async { await setAvatar("preset:\(name)") }

    func deletePhoto() async {
        guard var p = profile else { return }
        p.photo = nil; if p.avatar == "photo" { p.avatar = "preset:box" }
        profile = p; avatarImage = nil
        try? FileManager.default.removeItem(at: Self.avatarFile)
        do {
            try await supabase.functions.invoke("avatar-url", options: .init(body: ["op": "delete"]))
            // AnyJSON.null — чтобы в запрос ушёл явный null (Optional nil ключ просто пропускает)
            let patch: [String: AnyJSON] = ["photo": .null, "avatar": .string(p.avatar)]
            try await supabase.from("profiles").update(patch).eq("id", value: p.id).execute()
        } catch { print("photo delete:", error) }
    }

    /// Своё фото: квадрат 512 px → R2 по подписанной ссылке → profiles.avatar = ключ.
    func setPhoto(_ image: UIImage) async throws {
        guard var p = profile else { return }
        let square = image.squareCropped().resized(maxSide: 512)
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }
        avatarImage = square
        try? data.write(to: Self.avatarFile, options: .atomic)
        struct Ticket: Decodable { let key: String, url: String }
        let t: Ticket = try await supabase.functions.invoke("avatar-url", options: .init(body: ["op": "put"]))
        var req = URLRequest(url: URL(string: t.url)!)
        req.httpMethod = "PUT"; req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
        guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { throw URLError(.badServerResponse) }
        p.photo = t.key; p.avatar = "photo"; profile = p
        try await supabase.from("profiles").update(["avatar": "photo", "photo": t.key]).eq("id", value: p.id).execute()
    }

    private func fetchAvatar(key: String) async {
        struct Ticket: Decodable { let url: String }
        do {
            let t: Ticket = try await supabase.functions.invoke("avatar-url", options: .init(body: ["op": "get", "key": key]))
            let (data, _) = try await URLSession.shared.data(from: URL(string: t.url)!)
            if let img = UIImage(data: data) { avatarImage = img; try? data.write(to: Self.avatarFile, options: .atomic) }
        } catch { print("avatar get:", error) }
    }

    func setTwoFactor(_ on: Bool) async {
        guard var p = profile else { return }
        p.twoFactor = on; p.twoFactorVerifiedAt = Date(); profile = p
        struct Patch: Encodable { var two_factor: Bool; var two_factor_verified_at: Date }
        do { try await supabase.from("profiles").update(Patch(two_factor: on, two_factor_verified_at: Date())).eq("id", value: p.id).execute() } catch { print("2fa:", error) }
    }

    func markTwoFactorVerified() async {
        guard var p = profile else { return }
        p.twoFactorVerifiedAt = Date(); profile = p
        do { try await supabase.from("profiles").update(["two_factor_verified_at": Date()]).eq("id", value: p.id).execute() } catch { print("2fa verified:", error) }
    }

    /// Email сменили в Auth — продублировать в профиль.
    func setEmail(_ email: String) async {
        guard var p = profile else { return }
        p.email = email; profile = p
        do { try await supabase.from("profiles").update(["email": email]).eq("id", value: p.id).execute() } catch { print("email:", error) }
    }

    func clear() {
        profile = nil; usage = nil; identities = []; hasPassword = false; avatarImage = nil; loaded = false
        try? FileManager.default.removeItem(at: Self.avatarFile)
    }
}

// MARK: - Готовые аватарки (как в макете Account)

struct AvatarPreset: Identifiable, Hashable {
    let id: String      // имя в profiles.avatar после "preset:"
    let title: String
    let color: Color
    let symbol: String

    static let all: [AvatarPreset] = [
        .init(id: "box",   title: "Коробка", color: Theme.accent,      symbol: "shippingbox.fill"),
        .init(id: "home",  title: "Дом",     color: Color(hex: 0x3B4D74), symbol: "house.fill"),
        .init(id: "leaf",  title: "Росток",  color: Color(hex: 0x4D5F4A), symbol: "leaf.fill"),
        .init(id: "sun",   title: "Солнце",  color: Color(hex: 0xC9A27A), symbol: "sun.max.fill"),
        .init(id: "plane", title: "Самолёт", color: Theme.ink,          symbol: "paperplane.fill"),
        .init(id: "star",  title: "Звезда",  color: Color(hex: 0x8C6BB1), symbol: "star.fill"),
    ]
    static func named(_ avatar: String) -> AvatarPreset {
        let name = avatar.hasPrefix("preset:") ? String(avatar.dropFirst(7)) : avatar
        return all.first { $0.id == name } ?? all[0]
    }
}

/// Круглый аватар: своё фото или готовая картинка.
struct AvatarView: View {
    var profile: Profile?
    var image: UIImage?
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let image, profile?.hasCustomAvatar == true {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                let p = AvatarPreset.named(profile?.avatar ?? "preset:box")
                p.color
                Image(systemName: p.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Theme.onInk)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

extension UIImage {
    func squareCropped() -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: .init())
        return r.image { _ in draw(at: CGPoint(x: -origin.x, y: -origin.y)) }
    }
}
