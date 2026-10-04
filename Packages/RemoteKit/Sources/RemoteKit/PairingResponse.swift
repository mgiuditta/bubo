import CryptoKit
import Foundation

/// What the iPhone tells the Mac about itself, encrypted inside the ``PairingResponse``.
public struct DeviceEnrollment: Codable, Sendable, Equatable {
    /// The name the user gave the iPhone.
    public let deviceName: String
    /// The x9.63 public key of the iPhone's Secure Enclave signing key.
    public let signingKey: Data
    /// The signature of the pairing by that key: proves the iPhone holds it, and cost a Face ID.
    public let proof: Data
    /// The protocol version of the iPhone.
    public let protocolVersion: Int
}

/// The iPhone's answer to a QR: its key-agreement key and the encrypted enrollment.
///
/// Only the identifiers and the X25519 public key are in clear; the name and the signing key travel encrypted with
/// the pair's key, with the invitation ID as associated data.
public struct PairingResponse: Codable, Sendable, Equatable {
    /// The invitation being answered.
    public let invitationID: UUID
    /// The random identifier of the iPhone.
    public let deviceID: UUID
    /// The raw X25519 public key of the iPhone, fresh for this pairing.
    public let agreementKey: Data
    /// The ``DeviceEnrollment``, sealed with the pair's key.
    public let sealedEnrollment: Data

    /// Creates the response to `invitation`, signing the pairing with `signer` (Face ID on the iPhone).
    ///
    /// - Parameters:
    ///   - agreementKey: the iPhone's fresh X25519 key for this pairing.
    ///   - secrets: what ``PairingCrypto/secrets(privateKey:peerKey:invitation:deviceID:)`` derived on the iPhone.
    public init(
        to invitation: PairingInvitation,
        deviceID: UUID,
        deviceName: String,
        agreementKey: Curve25519.KeyAgreement.PublicKey,
        secrets: PairingSecrets,
        signer: some RemoteSigner
    ) throws {
        invitationID = invitation.id
        self.deviceID = deviceID
        self.agreementKey = agreementKey.rawRepresentation
        let message = Self.proofMessage(invitationID: invitation.id, deviceID: deviceID, agreementKey: self.agreementKey)
        let enrollment = DeviceEnrollment(
            deviceName: deviceName,
            signingKey: signer.publicKey.x963Representation,
            proof: try signer.signature(for: message).derRepresentation,
            protocolVersion: RemoteProtocol.version
        )
        sealedEnrollment = try RecordSealer(key: secrets.key).seal(enrollment, recordID: invitation.id.uuidString)
    }

    /// Opens the enrollment on the Mac and checks its proof.
    ///
    /// - Throws: ``PairingError/invalidResponse`` when it does not decrypt or the proof is wrong,
    ///   ``PairingError/incompatibleVersion`` for another protocol version.
    public func enrollment(using secrets: PairingSecrets) throws(PairingError) -> DeviceEnrollment {
        let enrollment: DeviceEnrollment
        do {
            enrollment = try RecordSealer(key: secrets.key)
                .open(DeviceEnrollment.self, from: sealedEnrollment, recordID: invitationID.uuidString)
        } catch {
            throw .invalidResponse
        }
        guard enrollment.protocolVersion == RemoteProtocol.version else { throw .incompatibleVersion }
        let message = Self.proofMessage(invitationID: invitationID, deviceID: deviceID, agreementKey: agreementKey)
        guard let key = try? P256.Signing.PublicKey(x963Representation: enrollment.signingKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: enrollment.proof),
              key.isValidSignature(signature, for: message)
        else { throw .invalidResponse }
        return enrollment
    }

    private static func proofMessage(invitationID: UUID, deviceID: UUID, agreementKey: Data) -> Data {
        var message = Data("bubo-remote/v1/pairing".utf8)
        message.appendField(invitationID.bytes)
        message.appendField(deviceID.bytes)
        message.appendField(agreementKey)
        return message
    }
}
