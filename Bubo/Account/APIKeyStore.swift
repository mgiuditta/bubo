import Foundation
import Security

/// One of the user's API keys, kept in the data protection keychain: the optional Anthropic key, or the key of an
/// OpenAI-compatible endpoint.
///
/// Readable only while the Mac is unlocked and never synced to iCloud. All
/// `SecItem` calls run on this actor, off the main actor.
actor APIKeyStore {
    /// The keychain service; tests pass their own to stay isolated.
    let service: String
    /// The item's account: one per provider, so each key is saved and removed on its own.
    let account: String

    /// Creates a store for the key `account` names among the items of `service`.
    init(service: String = "com.mgiuditta.bubo.api-key", account: String = "anthropic-api-key") {
        self.service = service
        self.account = account
    }

    /// Saves `key`, replacing any key already saved.
    func save(_ key: String) throws(KeychainError) {
        let value = Data(key.utf8)
        var add = baseQuery
        add[kSecValueData] = value
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updates = [kSecValueData: value] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updates)
            guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    /// Returns the saved key, or `nil` when there is none.
    func key() throws(KeychainError) -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Returns whether a key is saved, without reading it.
    func containsKey() throws(KeychainError) -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw KeychainError(status: status)
        }
    }

    /// Deletes the saved key; deleting when there is none is not an error.
    func delete() throws(KeychainError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}
