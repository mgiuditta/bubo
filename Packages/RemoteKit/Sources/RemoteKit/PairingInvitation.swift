import CryptoKit
import Foundation

/// What the Mac shows in the pairing QR: its key-agreement key, a one-time code and the expiry.
///
/// Valid for ``lifetime``; the one-time code is the salt of the key derivation, so a QR is good for one pairing only.
public struct PairingInvitation: Codable, Sendable, Equatable {
    /// How long a QR stays valid: 5 minutes (spec 21).
    public static let lifetime: TimeInterval = 5 * 60
    /// The scheme of the QR payload.
    static let scheme = "bubo-remote:"

    /// The invitation's random identifier; the iPhone's response refers to it.
    public let id: UUID
    /// The random identifier of the Mac.
    public let macID: UUID
    /// The Mac's name, shown on the iPhone.
    public let macName: String
    /// The raw X25519 public key of the Mac, fresh for every invitation.
    public let agreementKey: Data
    /// 16 random bytes, the salt of the key derivation.
    public let oneTimeCode: Data
    /// When the QR stops being valid.
    public let expiresAt: Date
    /// The protocol version of the Mac.
    public let protocolVersion: Int

    /// Creates an invitation for `agreementKey`, valid for ``lifetime`` from `now`.
    public init(macID: UUID, macName: String, agreementKey: Curve25519.KeyAgreement.PublicKey, now: Date = .now) {
        id = UUID()
        self.macID = macID
        self.macName = macName
        self.agreementKey = agreementKey.rawRepresentation
        oneTimeCode = .random(count: 16)
        expiresAt = now.addingTimeInterval(Self.lifetime)
        protocolVersion = RemoteProtocol.version
    }

    /// Reads the invitation from the text of a scanned QR.
    ///
    /// - Throws: ``PairingError/unreadableCode`` when the text is not a Bubo invitation.
    public init(qrPayload: String) throws(PairingError) {
        guard qrPayload.hasPrefix(Self.scheme),
              let data = Data(base64URLEncoded: String(qrPayload.dropFirst(Self.scheme.count))),
              let invitation = try? JSONDecoder().decode(Self.self, from: data)
        else { throw .unreadableCode }
        self = invitation
    }

    /// The text to encode in the QR.
    public var qrPayload: String {
        // Encoding a struct of plain values cannot fail.
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return Self.scheme + data.base64URLEncodedString()
    }

    /// Returns whether the QR is no longer valid at `date`.
    public func isExpired(at date: Date = .now) -> Bool {
        date >= expiresAt
    }
}

extension Data {
    /// Base64url without padding, short enough for a dense QR.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    /// Decodes base64url with or without padding.
    init?(base64URLEncoded text: String) {
        var base64 = text.replacing("-", with: "+").replacing("_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
