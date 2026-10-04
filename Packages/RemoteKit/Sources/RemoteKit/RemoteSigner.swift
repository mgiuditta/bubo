import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Signs Verdicts and Commands with a P-256 key; the Mac verifies with the public key it got at pairing.
public protocol RemoteSigner: Sendable {
    /// The public key the Mac stores at pairing.
    var publicKey: P256.Signing.PublicKey { get }
    /// Returns the signature of `message`.
    func signature(for message: Data) throws -> P256.Signing.ECDSASignature
}

/// A signing key in the Secure Enclave of the iPhone, usable only after Face ID with the current enrollment.
///
/// A new Face ID enrollment invalidates the key for good: the iPhone must pair again (spec 21).
public struct SecureEnclaveSigner: RemoteSigner {
    /// Why the Secure Enclave key cannot be made.
    public enum Failure: Error, Sendable {
        /// No Secure Enclave: the Simulator, or a Mac without one.
        case unavailable
        /// The access control or the key could not be created.
        case keyCreationFailed
    }

    private let key: SecureEnclave.P256.Signing.PrivateKey

    /// Restores the key from the opaque blob of ``dataRepresentation``, readable only by this Secure Enclave.
    ///
    /// - Parameter authenticationContext: The context that authorizes the key; one with a reuse duration lets the
    ///   Face ID that unlocked the iPhone for a notification's action sign without asking again.
    public init(dataRepresentation: Data, authenticationContext: LAContext? = nil) throws {
        key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation,
                                                         authenticationContext: authenticationContext)
    }

    private init(key: SecureEnclave.P256.Signing.PrivateKey) {
        self.key = key
    }

    /// Creates a new key in the Secure Enclave, bound to the current Face ID enrollment.
    public static func make() throws(Failure) -> SecureEnclaveSigner {
        #if targetEnvironment(simulator)
        throw .unavailable
        #else
        guard SecureEnclave.isAvailable else { throw .unavailable }
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        ) else { throw .keyCreationFailed }
        do {
            return SecureEnclaveSigner(key: try SecureEnclave.P256.Signing.PrivateKey(accessControl: access))
        } catch {
            throw .keyCreationFailed
        }
        #endif
    }

    /// The opaque, device-bound blob to keep in the keychain; it is not the private key.
    public var dataRepresentation: Data {
        key.dataRepresentation
    }

    public var publicKey: P256.Signing.PublicKey {
        key.publicKey
    }

    public func signature(for message: Data) throws -> P256.Signing.ECDSASignature {
        try key.signature(for: message)
    }
}
