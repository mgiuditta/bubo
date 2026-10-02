import CryptoKit
import Foundation
import RemoteKit
import Testing

struct PairingTests {
    @Test func qrPayloadRoundTrips() throws {
        let fixture = try PairingFixture()
        let read = try PairingInvitation(qrPayload: fixture.invitation.qrPayload)
        #expect(read == fixture.invitation)
    }

    @Test func foreignQRIsUnreadable() {
        #expect(throws: PairingError.unreadableCode) {
            try PairingInvitation(qrPayload: "https://example.com")
        }
    }

    @Test func invitationExpiresAfterFiveMinutes() throws {
        let now = Date.now
        let fixture = try PairingFixture(now: now)
        #expect(!fixture.invitation.isExpired(at: now.addingTimeInterval(299)))
        #expect(fixture.invitation.isExpired(at: now.addingTimeInterval(300)))
    }

    @Test func bothSidesDeriveTheSameKeyAndCode() throws {
        let fixture = try PairingFixture()
        let mac = try fixture.macSecrets()
        let sealed = try RecordSealer(key: mac.key).seal(Data("ciao".utf8), recordID: "r1")
        #expect(try RecordSealer(key: fixture.deviceSecrets.key).open(sealed, recordID: "r1") == Data("ciao".utf8))
        #expect(mac.verificationCode == fixture.deviceSecrets.verificationCode)
        #expect(mac.verificationCode.count == 6)
        #expect(mac.verificationCode.allSatisfy(\.isASCII) && mac.verificationCode.allSatisfy(\.isNumber))
    }

    @Test func macOpensTheEnrollmentAndChecksTheProof() throws {
        let fixture = try PairingFixture()
        let enrollment = try fixture.response.enrollment(using: fixture.macSecrets())
        #expect(enrollment.deviceName == "iPhone di prova")
        #expect(enrollment.signingKey == fixture.signer.publicKey.x963Representation)
    }

    /// Someone who photographed the QR answers too: their code differs from the user's iPhone.
    @Test func anotherResponderGetsAnotherCode() throws {
        let fixture = try PairingFixture()
        let intruder = try PairingCrypto.secrets(
            privateKey: Curve25519.KeyAgreement.PrivateKey(),
            peerKey: fixture.invitation.agreementKey,
            invitation: fixture.invitation,
            deviceID: UUID()
        )
        #expect(intruder.verificationCode != fixture.deviceSecrets.verificationCode)
    }

    @Test func enrollmentMovedToAnotherDeviceIsRefused() throws {
        let fixture = try PairingFixture()
        let tampered = try fixture.response.replacingDeviceID(UUID())
        let secrets = try PairingCrypto.secrets(
            privateKey: fixture.macKey,
            peerKey: tampered.agreementKey,
            invitation: fixture.invitation,
            deviceID: tampered.deviceID
        )
        #expect(throws: PairingError.invalidResponse) {
            try tampered.enrollment(using: secrets)
        }
    }
}

private extension PairingResponse {
    /// The same response with another device ID, as a tampered record would carry.
    func replacingDeviceID(_ deviceID: UUID) throws -> PairingResponse {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any])
        json["deviceID"] = deviceID.uuidString
        return try JSONDecoder().decode(PairingResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
