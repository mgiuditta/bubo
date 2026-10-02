import CryptoKit
import Foundation

/// Encrypts and decrypts the payload of a Telecomando record with the pair's key.
///
/// ChaCha20-Poly1305 with a random nonce for every seal, and the record ID as associated data: a payload moved to
/// another record does not open.
public struct RecordSealer: Sendable {
    /// Why a payload did not open.
    public enum Failure: Error, Equatable, Sendable {
        /// Wrong key, wrong record ID or altered bytes.
        case unreadable
    }

    private let key: SymmetricKey

    /// Creates a sealer for the pair whose record key is `key`.
    public init(key: SymmetricKey) {
        self.key = key
    }

    /// Returns `plaintext` encrypted for the record `recordID`: nonce, ciphertext and tag.
    public func seal(_ plaintext: Data, recordID: String) throws -> Data {
        try ChaChaPoly.seal(plaintext, using: key, authenticating: Data(recordID.utf8)).combined
    }

    /// Returns the plaintext of `sealed`, which must belong to the record `recordID`.
    public func open(_ sealed: Data, recordID: String) throws(Failure) -> Data {
        do {
            let box = try ChaChaPoly.SealedBox(combined: sealed)
            return try ChaChaPoly.open(box, using: key, authenticating: Data(recordID.utf8))
        } catch {
            throw .unreadable
        }
    }

    /// Returns `value` encoded as JSON and encrypted for the record `recordID`.
    public func seal(_ value: some Encodable, recordID: String) throws -> Data {
        try seal(JSONEncoder().encode(value), recordID: recordID)
    }

    /// Returns the value of type `type` that `sealed` carries for the record `recordID`.
    public func open<Value: Decodable>(_ type: Value.Type, from sealed: Data, recordID: String) throws(Failure) -> Value {
        let data = try open(sealed, recordID: recordID)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .unreadable
        }
    }
}
