import Foundation
import CryptoKit
import CommonCrypto
import LocalAuthentication
import Security
import Observation
import Supabase

/// «Сейф» (ТЗ §10а): ключ выводится из пароля сейфа (PBKDF2-HMAC-SHA256, соль из профиля), живёт только в памяти,
/// пока приложение на экране; названия вещей и фото шифруются AES-GCM. Сервер видит только шифртекст.
/// Проверка пароля — расшифровкой «проверочной строки» из профиля (profiles.safe_verifier).
/// Face ID — по желанию: ключ кладётся в Keychain под биометрией этого устройства.
@Observable
final class SafeSession: @unchecked Sendable {
    static let shared = SafeSession()
    /// Ключ — под замком: шифрование/расшифровка зовутся и с главного потока, и из загрузки фото.
    @ObservationIgnored private let keyLock = NSLock()
    @ObservationIgnored private var _key: SymmetricKey?
    private var key: SymmetricKey? {
        get { keyLock.lock(); defer { keyLock.unlock() }; return _key }
        set { keyLock.lock(); _key = newValue; keyLock.unlock(); Task { @MainActor in self.isOpen = newValue != nil } }
    }
    /// Наблюдаемое состояние для экранов (меняется на главном потоке).
    @MainActor private(set) var isOpen = false
    /// Включён ли вход по Face ID на этом устройстве (ключ лежит в Keychain).
    @MainActor private(set) var biometryEnabled = UserDefaults.standard.bool(forKey: "safe_biometry")

    static let iterations = 200_000
    private static let verifierText = "boxno-safe-v1"
    private static let keychainAccount = "co.boxnumber.safe.key"

    // MARK: пароль

    /// Пароль ещё не задан (в профиле нет соли).
    @MainActor var needsSetup: Bool { ProfileStore.shared.profile?.safeSalt == nil }

    /// Первый сейф. Содержимое шифруется случайным мастер-ключом; из пароля выводится ключ-обёртка (PBKDF2),
    /// которым мастер-ключ «заворачивается» и кладётся в профиль. Так смена пароля не требует перешифровки.
    /// Проверочная строка зашифрована мастер-ключом. Пароль не хранится нигде.
    @MainActor func setup(password: String) async throws {
        let salt = Self.randomBytes(16)
        let master = SymmetricKey(size: .bits256)
        let kek = try await Self.derive(password: password, salt: salt, iterations: Self.iterations)
        let wrapped = try AES.GCM.seal(master.withUnsafeBytes { Data($0) }, using: kek).combined!
        let verifier = try AES.GCM.seal(Data(Self.verifierText.utf8), using: master).combined!
        try await ProfileStore.shared.setSafe(salt: salt.base64EncodedString(), verifier: verifier.base64EncodedString(),
                                              iterations: Self.iterations, wrappedKey: wrapped.base64EncodedString())
        key = master
    }

    /// Мастер-ключ по паролю: разворачиваем обёртку (или, для сейфов без обёртки, мастер = ключ из пароля)
    /// и сверяем проверочную строку. nil — пароль не подошёл.
    @MainActor private func unlockMaster(password: String) async throws -> SymmetricKey? {
        guard let p = ProfileStore.shared.profile, let saltB64 = p.safeSalt, let salt = Data(base64Encoded: saltB64),
              let verB64 = p.safeVerifier, let verifier = Data(base64Encoded: verB64) else { throw SafeError.notSetUp }
        let kek = try await Self.derive(password: password, salt: salt, iterations: p.safeKdfIter ?? Self.iterations)
        var master = kek
        if let wB64 = p.safeWrappedKey, let wrapped = Data(base64Encoded: wB64) {
            guard let box = try? AES.GCM.SealedBox(combined: wrapped), let raw = try? AES.GCM.open(box, using: kek) else { return nil }
            master = SymmetricKey(data: raw)
        }
        guard let box = try? AES.GCM.SealedBox(combined: verifier), let plain = try? AES.GCM.open(box, using: master),
              String(decoding: plain, as: UTF8.self) == Self.verifierText else { return nil }
        return master
    }

    /// Открыть сейф паролем. false — пароль не подошёл.
    @MainActor func open(password: String) async throws -> Bool {
        guard let master = try await unlockMaster(password: password) else { return false }
        key = master
        return true
    }

    /// Сменить пароль: проверяем старый, заворачиваем тот же мастер-ключ новым — содержимое и Face ID не трогаются.
    /// false — старый пароль не подошёл.
    @MainActor func changePassword(old: String, new: String) async throws -> Bool {
        guard let master = try await unlockMaster(password: old) else { return false }
        let salt = Self.randomBytes(16)
        let kek = try await Self.derive(password: new, salt: salt, iterations: Self.iterations)
        let wrapped = try AES.GCM.seal(master.withUnsafeBytes { Data($0) }, using: kek).combined!
        let verifier = try AES.GCM.seal(Data(Self.verifierText.utf8), using: master).combined!
        try await ProfileStore.shared.setSafe(salt: salt.base64EncodedString(), verifier: verifier.base64EncodedString(),
                                              iterations: Self.iterations, wrappedKey: wrapped.base64EncodedString())
        key = master
        return true
    }

    private static func randomBytes(_ n: Int) -> Data {
        var d = Data(count: n); _ = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }; return d
    }

    /// Закрыть: ключ стирается из памяти, расшифрованные картинки — из кеша.
    @MainActor func lock() {
        guard key != nil else { return }
        key = nil; isOpen = false
        PhotoStore.dropMemoryCache()
    }

    // MARK: Face ID

    @MainActor var biometryAvailable: Bool {
        var e: NSError?; return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }

    /// Положить текущий ключ в Keychain под Face ID (только пока сейф открыт).
    @MainActor func enableBiometry() throws {
        guard let key else { throw SafeError.locked }
        let data = key.withUnsafeBytes { Data($0) }
        var err: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &err) else {
            throw err?.takeRetainedValue() ?? SafeError.keychain
        }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.keychainAccount]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessControl as String] = access
        let st = SecItemAdd(add as CFDictionary, nil)
        guard st == errSecSuccess else { throw SafeError.keychain }
        biometryEnabled = true
        UserDefaults.standard.set(true, forKey: "safe_biometry")
    }

    @MainActor func disableBiometry() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.keychainAccount] as CFDictionary)
        biometryEnabled = false
        UserDefaults.standard.set(false, forKey: "safe_biometry")
    }

    /// Открыть по Face ID: система сама спросит лицо при чтении из Keychain.
    @MainActor func openWithBiometry() async -> Bool {
        let ctx = LAContext(); ctx.localizedReason = "Открыть сейф"
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.keychainAccount,
                                kSecReturnData as String: true, kSecUseAuthenticationContext as String: ctx]
        let data: Data? = await Task.detached {
            var out: CFTypeRef?
            return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
        }.value
        guard let data else { return false }
        key = SymmetricKey(data: data)
        return true
    }

    // MARK: шифрование

    func encrypt(_ data: Data) throws -> Data {
        guard let key else { throw SafeError.locked }
        return try AES.GCM.seal(data, using: key).combined!
    }
    func decrypt(_ data: Data) -> Data? {
        guard let key, let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
    func encrypt(_ text: String) throws -> String { try encrypt(Data(text.utf8)).base64EncodedString() }
    func decrypt(_ b64: String) -> String? {
        guard let d = Data(base64Encoded: b64), let plain = decrypt(d) else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }

    // MARK: PBKDF2

    private static func derive(password: String, salt: Data, iterations: Int) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            var out = Data(count: 32)
            let pw = Array(password.utf8)
            let st = out.withUnsafeMutableBytes { outPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                         saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
            guard st == kCCSuccess else { throw SafeError.kdf }
            return SymmetricKey(data: out)
        }.value
    }

    enum SafeError: LocalizedError {
        case notSetUp, locked, keychain, kdf
        var errorDescription: String? {
            switch self {
            case .notSetUp: "Пароль сейфа не задан"
            case .locked: "Сейф закрыт"
            case .keychain: "Не удалось сохранить ключ для Face ID"
            case .kdf: "Не удалось вычислить ключ"
            }
        }
    }
}
