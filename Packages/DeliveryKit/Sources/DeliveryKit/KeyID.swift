import CryptoKit
import Foundation

/// The identifier of a Macchina's key: the first 8 bytes of the SHA-256 of its public key in x9.63 form.
///
/// In the clear in every `.bubo` header, so the right error comes before decrypting (spec 24).
public struct KeyID: Hashable, Sendable, CustomStringConvertible {
    /// The 8 bytes.
    public let bytes: Data

    /// The identifier of `publicKey`.
    public init(_ publicKey: P256.KeyAgreement.PublicKey) {
        bytes = Data(SHA256.hash(data: publicKey.x963Representation).prefix(Self.byteCount))
    }

    /// The identifier read from a header; `nil` unless `bytes` has exactly 8 bytes.
    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = Data(bytes)
    }

    /// No key: the recipient of a Biglietto, which is not encrypted for anyone.
    public static let none = KeyID(bytes: Data(count: byteCount))!

    /// The size of an identifier, in bytes.
    public static let byteCount = 8

    /// The identifier in lowercase hexadecimal, 16 characters.
    public var description: String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return byte < 0x10 ? "0" + digits : digits
        }.joined()
    }
}
