import CryptoKit
import Foundation

/// Why the Mac refuses a Verdict.
public enum VerdictRejection: Error, Equatable, Sendable {
    /// Signed by an iPhone that was never paired with this Mac.
    case unknownDevice
    /// Signed by an iPhone whose pairing was revoked.
    case revokedDevice
    /// The signature does not match the Verdict.
    case invalidSignature
    /// Addressed to another Mac.
    case otherMac
    /// Older than 10 minutes, or dated in the future.
    case expired
    /// A nonce already seen: a replay.
    case repeatedNonce
}

/// Checks the Verdicts that reach the Mac: signature of a paired, unrevoked iPhone, this Mac, age, fresh nonce.
///
/// Whether the Request is still open is for the caller: the verifier knows only the Verdict.
public struct VerdictVerifier: Sendable {
    /// A Verdict older than this is refused: 10 minutes.
    public static let maximumAge: TimeInterval = 10 * 60
    /// How far in the future a Verdict may be dated, for clocks out of step.
    static let clockSkew: TimeInterval = 60

    /// The Mac this verifier works for.
    public let macID: UUID
    private var signingKeys: [UUID: P256.Signing.PublicKey] = [:]
    private var revokedDevices: Set<UUID> = []
    /// The nonces of the accepted Verdicts, with when they were seen, kept for ``maximumAge``.
    private var seenNonces: [Data: Date] = [:]

    /// Creates a verifier for the Mac `macID`, with no paired iPhone.
    public init(macID: UUID) {
        self.macID = macID
    }

    /// Accepts Verdicts from the iPhone `deviceID`, signed by `signingKey`.
    public mutating func trust(deviceID: UUID, signingKey: P256.Signing.PublicKey) {
        signingKeys[deviceID] = signingKey
        revokedDevices.remove(deviceID)
    }

    /// Refuses from now on every Verdict of the iPhone `deviceID`.
    public mutating func revoke(deviceID: UUID) {
        signingKeys[deviceID] = nil
        revokedDevices.insert(deviceID)
    }

    /// Returns the Verdict when it passes every check, and remembers its nonce.
    public mutating func verify(_ signed: SignedVerdict, now: Date = .now) throws(VerdictRejection) -> Verdict {
        let verdict = signed.verdict
        guard !revokedDevices.contains(signed.deviceID) else { throw .revokedDevice }
        guard let key = signingKeys[signed.deviceID] else { throw .unknownDevice }
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: signed.signature),
              key.isValidSignature(signature, for: verdict.signedMessage)
        else { throw .invalidSignature }
        guard verdict.macID == macID else { throw .otherMac }
        let age = now.timeIntervalSince(verdict.issuedAt)
        guard age <= Self.maximumAge, age >= -Self.clockSkew else { throw .expired }
        seenNonces = seenNonces.filter { now.timeIntervalSince($0.value) <= Self.maximumAge + Self.clockSkew }
        guard seenNonces[verdict.nonce] == nil else { throw .repeatedNonce }
        seenNonces[verdict.nonce] = now
        return verdict
    }
}
