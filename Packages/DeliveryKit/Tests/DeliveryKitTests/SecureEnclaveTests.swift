import CryptoKit
import DeliveryKit
import Foundation
import Testing

/// HPKE auth with both keys in the Secure Enclave (gate of #274, on one Mac): 50 MB in chunks of 1 MiB.
///
/// Skipped where there is no Secure Enclave (a virtual machine, a Mac without T2 or Apple silicon).
@Suite(.enabled(if: SecureEnclave.isAvailable, "No Secure Enclave on this Mac"))
struct SecureEnclaveTests {
    @Test func opensFiftyMegabytesBetweenSecureEnclaveKeys() throws {
        let sender = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        let recipient = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        let impostor = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        var generator = SystemRandomNumberGenerator()
        let content = Data((0..<(50 * DeliveryCipher.chunkSize / 8)).flatMap { _ in
            withUnsafeBytes(of: generator.next() as UInt64) { Array($0) }
        })

        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        let opened = try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        #expect(SHA256.hash(data: opened) == SHA256.hash(data: content))

        var altered = file
        altered[altered.count / 3] ^= 0x80
        #expect(throws: DeliveryError.damaged) { try DeliveryCipher.open(altered, with: recipient, from: sender.publicKey) }

        var chunks = Chunks(file)
        chunks.sealed.remove(at: 17)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(chunks.file, with: recipient, from: sender.publicKey)
        }

        #expect(throws: DeliveryError.otherSender) {
            try DeliveryCipher.open(file, with: recipient, from: impostor.publicKey)
        }
        // The impostor sealing with the sender's key identifier in the header: the authentication does not pass.
        var forged = try DeliveryCipher.seal(Data(content.prefix(3 * DeliveryCipher.chunkSize)), for: recipient.publicKey,
                                             from: impostor)
        forged.replaceSubrange(14..<22, with: KeyID(sender.publicKey).bytes)
        #expect(throws: DeliveryError.damaged) { try DeliveryCipher.open(forged, with: recipient, from: sender.publicKey) }
    }

    @Test func keyComesBackFromItsReference() throws {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        let restored = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: key.dataRepresentation)
        #expect(restored.publicKey.x963Representation == key.publicKey.x963Representation)
    }
}
