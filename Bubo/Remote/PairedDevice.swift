import Foundation

/// An iPhone paired with this Mac: its signing key and the record key of the pair.
///
/// Kept whole in the keychain, because the record key is a secret.
nonisolated struct PairedDevice: Codable, Identifiable, Sendable, Equatable {
    /// The random identifier the iPhone chose.
    let id: UUID
    /// The name the iPhone sent, encrypted, at pairing.
    let name: String
    /// The x9.63 public key of the iPhone's Secure Enclave signing key.
    let signingKey: Data
    /// The raw ChaCha20-Poly1305 key of the pair's records.
    let recordKey: Data
    /// When the pairing was confirmed.
    let pairedAt: Date
}
