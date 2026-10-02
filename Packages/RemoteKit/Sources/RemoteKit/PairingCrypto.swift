import CryptoKit
import Foundation

/// The secrets of one Mac–iPhone pair: the record key and the 6-digit verification code.
public struct PairingSecrets: Sendable {
    /// The ChaCha20-Poly1305 key that encrypts every record of the pair.
    public let key: SymmetricKey
    /// The code shown on both screens; equal codes mean nobody else answered the QR.
    public let verificationCode: String
}

/// Key agreement of the pairing: X25519, then HKDF-SHA256 with the one-time code as salt (spec 21).
public enum PairingCrypto {
    /// Derives the pair's secrets on either side.
    ///
    /// The Mac passes its private key and the iPhone's public key; the iPhone passes its private key and the
    /// Mac's key from the invitation. Both get the same secrets.
    /// - Throws: ``PairingError/invalidResponse`` when `peerKey` is not an X25519 public key.
    public static func secrets(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerKey: Data,
        invitation: PairingInvitation,
        deviceID: UUID
    ) throws(PairingError) -> PairingSecrets {
        let shared: SharedSecret
        do {
            let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey)
            shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        } catch {
            throw .invalidResponse
        }
        let pair = invitation.macID.bytes + deviceID.bytes
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: invitation.oneTimeCode,
            sharedInfo: Data("bubo-remote/v1/record-key".utf8) + pair,
            outputByteCount: 32
        )
        let codeKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: invitation.oneTimeCode,
            sharedInfo: Data("bubo-remote/v1/verification-code".utf8) + pair,
            outputByteCount: 8
        )
        let number = codeKey.withUnsafeBytes { bytes in
            bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        }
        let digits = String(number % 1_000_000)
        return PairingSecrets(
            key: key,
            verificationCode: String(repeating: "0", count: 6 - digits.count) + digits
        )
    }
}
