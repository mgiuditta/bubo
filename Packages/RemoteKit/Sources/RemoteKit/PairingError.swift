import Foundation

/// Why a pairing step failed.
public enum PairingError: Error, Equatable, Sendable {
    /// The scanned code is not a Bubo invitation.
    case unreadableCode
    /// The QR is older than 5 minutes.
    case expired
    /// The other side speaks another protocol version.
    case incompatibleVersion
    /// The response does not decrypt, or its proof of the signing key is wrong.
    case invalidResponse
}
