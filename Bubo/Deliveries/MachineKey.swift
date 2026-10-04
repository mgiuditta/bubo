import CryptoKit
import Foundation
import Security

/// The key of this Macchina for the Consegne: a P-256 key-agreement key in the Secure Enclave (spec 24, ADR 0008).
///
/// Created the first time it is needed, with `.privateKeyUsage`. The private key never leaves the Secure Enclave:
/// what is kept is its `dataRepresentation`, an opaque reference that only this Secure Enclave can use, in the
/// keychain (`WhenUnlockedThisDeviceOnly`, never synced). Nothing in Bubo exports the key.
nonisolated struct MachineKey: Sendable {
    /// Why the key is not usable.
    enum Failure: Error, Equatable {
        /// This Mac has no Secure Enclave: it cannot receive Consegne.
        case noSecureEnclave
        /// The keychain refused the reference, with this status.
        case keychain(OSStatus)
        /// The Secure Enclave refused to create or restore the key.
        case secureEnclave
    }

    /// Where the key's reference is kept.
    let storage: any MachineKeyStorage

    /// The key in the app: its reference in the keychain.
    static let live = MachineKey(storage: MachineKeyKeychain())

    /// The private key, created in the Secure Enclave the first time.
    ///
    /// - Throws: ``Failure``.
    func privateKey() async throws(Failure) -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        guard Self.isSecureEnclaveAvailable else { throw .noSecureEnclave }
        if let reference = try await storage.reference() {
            do {
                return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: reference)
            } catch {
                // Not from this Secure Enclave, e.g. a keychain restored on another Mac: never replaced silently,
                // since it would change the Biglietto that others have verified.
                throw .secureEnclave
            }
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           .privateKeyUsage, &error),
              let key = try? SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        else { throw .secureEnclave }
        try await storage.save(key.dataRepresentation)
        return key
    }

    /// Whether this Mac has a Secure Enclave.
    static var isSecureEnclaveAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        SecureEnclave.isAvailable
        #endif
    }
}

/// Where the reference of the Secure Enclave key is kept: the keychain in the app, memory in the tests.
nonisolated protocol MachineKeyStorage: Sendable {
    /// The saved reference, or `nil` when there is none.
    func reference() async throws(MachineKey.Failure) -> Data?
    /// Saves `reference`, replacing any saved one.
    func save(_ reference: Data) async throws(MachineKey.Failure)
}

/// The reference in the data protection keychain, readable only while the Mac is unlocked, never synced. All
/// `SecItem` calls run on this actor, off the main actor.
actor MachineKeyKeychain: MachineKeyStorage {
    /// The keychain service of the item.
    private let service = "com.mgiuditta.bubo.machine-key"
    /// The item's account.
    private let account = "consegna"

    func reference() throws(MachineKey.Failure) -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw .keychain(errSecDecode) }
            return data
        case errSecItemNotFound:
            return nil
        default:
            // errSecInteractionNotAllowed included: the Mac is locked, the reference is still there.
            throw .keychain(status)
        }
    }

    func save(_ reference: Data) throws(MachineKey.Failure) {
        var add = baseQuery
        add[kSecValueData] = reference
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: reference] as CFDictionary)
            guard update == errSecSuccess else { throw .keychain(update) }
        default:
            throw .keychain(status)
        }
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
