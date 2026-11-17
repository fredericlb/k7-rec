// A password kept in the Keychain, never in UserDefaults or a file.
import Foundation
import Security

protocol SecretStore: Sendable {
    func secret(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

struct KeychainStore: SecretStore {
    private let service = "se.frediver.rehearsal"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func secret(for key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func secret(for key: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func set(_ value: String?, for key: String) { lock.lock(); values[key] = value; lock.unlock() }
}
