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
@MainActor
@Observable
final class SafeSession {
    static let shared = SafeSession()
    private(set) var key: SymmetricKey?
    var isOpen: Bool { key != nil }
    /// Включён ли вход по Face ID на этом устройстве (ключ лежит в Keychain).
    private(set) var biometryEnabled = UserDefaults.standard.bool(forKey: "safe_biometry")

    static let iterations = 200_000
    private static let verifierText = "boxno-safe-v1"
    private static let keychainAccount = "co.boxnumber.safe.key"

    // MARK: пароль

    /// Пароль ещё не задан (в профиле нет соли).
    var needsSetup: Bool { ProfileStore.shared.profile?.safeSalt == nil }

    /// Первый сейф: соль + ключ + проверочная строка → профиль. Пароль не хранится нигде.
    func setup(password: String) async throws {
        var salt = Data(count: 16); _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let k = try await Self.derive(password: password, salt: salt, iterations: Self.iterations)
        let verifier = try AES.GCM.seal(Data(Self.verifierText.utf8), using: k).combined!
        try await ProfileStore.shared.setSafe(salt: salt.base64EncodedString(), verifier: verifier.base64EncodedString(), iterations: Self.iterations)
        key = k
    }

    /// Открыть сейф паролем. false — пароль не подошёл.
    func open(password: String) async throws -> Bool {
        guard let p = ProfileStore.shared.profile, let saltB64 = p.safeSalt, let salt = Data(base64Encoded: saltB64),
              let verB64 = p.safeVerifier, let verifier = Data(base64Encoded: verB64) else { throw SafeError.notSetUp }
        let k = try await Self.derive(password: password, salt: salt, iterations: p.safeKdfIter ?? Self.iterations)
        guard let box = try? AES.GCM.SealedBox(combined: verifier), let plain = try? AES.GCM.open(box, using: k),
              String(decoding: plain, as: UTF8.self) == Self.verifierText else { return false }
        key = k
        return true
    }

    /// Закрыть: ключ стирается из памяти, расшифрованные картинки — из кеша.
    func lock() {
        guard key != nil else { return }
        key = nil
        PhotoStore.dropMemoryCache()
    }

    // MARK: Face ID

    var biometryAvailable: Bool {
        var e: NSError?; return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }

    /// Положить текущий ключ в Keychain под Face ID (только пока сейф открыт).
    func enableBiometry() throws {
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

    func disableBiometry() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.keychainAccount] as CFDictionary)
        biometryEnabled = false
        UserDefaults.standard.set(false, forKey: "safe_biometry")
    }

    /// Открыть по Face ID: система сама спросит лицо при чтении из Keychain.
    func openWithBiometry() async -> Bool {
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
