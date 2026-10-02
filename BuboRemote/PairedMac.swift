import Foundation

/// A Mac this iPhone is paired with: the pair's record key and the Secure Enclave signing key.
///
/// Kept whole in the keychain, because the record key is a secret; the signing key is only its opaque blob,
/// usable by this Secure Enclave alone.
nonisolated struct PairedMac: Codable, Identifiable, Sendable, Equatable {
    /// The random identifier of the Mac.
    let id: UUID
    /// The Mac's name, from the QR.
    let name: String
    /// The raw ChaCha20-Poly1305 key of the pair's records.
    let recordKey: Data
    /// The `dataRepresentation` of the Secure Enclave key that signs Verdicts for this Mac.
    let signingKey: Data
    /// When the pairing was made.
    let pairedAt: Date
}
