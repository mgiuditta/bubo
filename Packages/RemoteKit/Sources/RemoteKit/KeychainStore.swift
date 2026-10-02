import Foundation
import Security

/// A keychain call that failed, with its `OSStatus`. Never carries the secret.
public struct KeychainFailure: Error, Equatable, Sendable {
    /// The status returned by the `SecItem` call.
    public let status: OSStatus
}

/// Codable items in the data protection keychain, one generic-password item per item ID.
///
/// For the pairings of both sides: each item holds a pair's record key. Readable after the first unlock, also with
/// the screen locked, because the Telecomando works when the user is away (the iPhone's notification extension, the
/// locked Mac). Never synced, never in a backup. All `SecItem` calls run on this actor, off the main actor.
public actor KeychainStore<Item: Codable & Sendable & Identifiable> where Item.ID == UUID {
    /// The keychain service of the items.
    public let service: String

    /// Creates a store over the items of `service`.
    public init(service: String) {
        self.service = service
    }

    /// Every item; one that does not decode, from another version, is skipped.
    public func items() throws(KeychainFailure) -> [Item] {
        try itemsBlocking()
    }

    /// Every item, read on the caller's thread: only for code already off the main actor that cannot wait, such as
    /// the iPhone's notification extension.
    public nonisolated func itemsBlocking() throws(KeychainFailure) -> [Item] {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [Data] else { throw KeychainFailure(status: errSecDecode) }
            return items.compactMap { try? JSONDecoder().decode(Item.self, from: $0) }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainFailure(status: status)
        }
    }

    /// Saves `item`, replacing the one with the same ID.
    public func save(_ item: Item) throws(KeychainFailure) {
        guard let value = try? JSONEncoder().encode(item) else { throw KeychainFailure(status: errSecParam) }
        var add = query(for: item.id)
        add[kSecValueData] = value
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = SecItemUpdate(query(for: item.id) as CFDictionary, [kSecValueData: value] as CFDictionary)
            guard update == errSecSuccess else { throw KeychainFailure(status: update) }
        default:
            throw KeychainFailure(status: status)
        }
    }

    /// Deletes the item `id`; deleting one that is not there is not an error.
    public func delete(id: UUID) throws(KeychainFailure) {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
    }

    private func query(for id: UUID) -> [CFString: Any] {
        var query = baseQuery
        query[kSecAttrAccount] = id.uuidString
        return query
    }

    private nonisolated var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}
