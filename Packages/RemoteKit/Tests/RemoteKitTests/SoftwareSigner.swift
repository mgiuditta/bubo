import CryptoKit
import Foundation
import RemoteKit

/// A software P-256 key in place of the Secure Enclave, which tests cannot use.
struct SoftwareSigner: RemoteSigner {
    let key = P256.Signing.PrivateKey()

    var publicKey: P256.Signing.PublicKey { key.publicKey }

    func signature(for message: Data) throws -> P256.Signing.ECDSASignature {
        try key.signature(for: message)
    }
}

/// A Mac and an iPhone halfway through pairing: the QR has been scanned, the response sent.
struct PairingFixture {
    let macKey = Curve25519.KeyAgreement.PrivateKey()
    let deviceKey = Curve25519.KeyAgreement.PrivateKey()
    let deviceID = UUID()
    let signer = SoftwareSigner()
    let invitation: PairingInvitation
    let deviceSecrets: PairingSecrets
    let response: PairingResponse

    init(now: Date = .now) throws {
        invitation = PairingInvitation(macID: UUID(), macName: "Mac di prova", agreementKey: macKey.publicKey, now: now)
        deviceSecrets = try PairingCrypto.secrets(
            privateKey: deviceKey,
            peerKey: invitation.agreementKey,
            invitation: invitation,
            deviceID: deviceID
        )
        response = try PairingResponse(
            to: invitation,
            deviceID: deviceID,
            deviceName: "iPhone di prova",
            agreementKey: deviceKey.publicKey,
            secrets: deviceSecrets,
            signer: signer
        )
    }

    /// The secrets the Mac derives from the response.
    func macSecrets() throws -> PairingSecrets {
        try PairingCrypto.secrets(
            privateKey: macKey,
            peerKey: response.agreementKey,
            invitation: invitation,
            deviceID: response.deviceID
        )
    }
}
