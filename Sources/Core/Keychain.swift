import Foundation
import Security

enum Keychain {
    static let service = "tn.achraf.ultratranscribe"
    /// Keys saved before the achraf.tn rebrand are moved to the new service on first read.
    private static let legacyService = "tn.ashref.ultratranscribe"
    static func read() -> String {
        if let key = stored(in: service) { return key }
        guard let legacy = stored(in: legacyService), (try? save(legacy)) != nil else { return "" }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: legacyService, kSecAttrAccount as String: "openrouter"] as CFDictionary)
        return legacy
    }
    private static func stored(in service: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "openrouter", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "openrouter"]
        if value.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw AppError.message("Could not remove the key from Keychain (\(result)).") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppError.message("Could not store the key in Keychain (\(added)).") }
        } else if result != errSecSuccess { throw AppError.message("Could not update Keychain (\(result)).") }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): return message } }
}
