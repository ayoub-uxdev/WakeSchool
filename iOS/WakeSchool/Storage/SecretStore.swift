import Foundation
import Security

/// Stockage des secrets (mots de passe, jetons). Jamais UserDefaults, jamais SwiftData, jamais Git.
protocol SecretStore {
    func set(_ data: Data, for key: String) throws
    func data(for key: String) throws -> Data?
    func remove(_ key: String) throws
}

enum SecretStoreError: LocalizedError, Equatable {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Erreur Keychain (\(status))."
        }
    }
}

/// Implémentation Keychain (kSecClassGenericPassword), accessible après le 1er déverrouillage
/// pour permettre une synchronisation en arrière-plan, et non migrable vers un autre appareil.
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = "com.ayoub.wakeschool") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func set(_ data: Data, for key: String) throws {
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecretStoreError.keychain(updateStatus) }

        var query = baseQuery(key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecretStoreError.keychain(addStatus) }
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        return result as? Data
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}

/// Implémentation mémoire pour les tests et les previews. Ne persiste rien.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws { storage[key] = data }
    func data(for key: String) throws -> Data? { storage[key] }
    func remove(_ key: String) throws { storage[key] = nil }
}

/// Lecture/écriture typée des identifiants Pronote dans un `SecretStore`.
struct CredentialsStore {
    private static let key = "pronote.credentials"
    let store: SecretStore

    func save(_ credentials: PronoteCredentials) throws {
        try store.set(try JSONEncoder().encode(credentials), for: Self.key)
    }

    func load() throws -> PronoteCredentials? {
        guard let data = try store.data(for: Self.key) else { return nil }
        return try JSONDecoder().decode(PronoteCredentials.self, from: data)
    }

    func delete() throws {
        try store.remove(Self.key)
    }
}
