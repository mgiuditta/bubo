import CryptoKit
import Foundation
import RemoteKit
import Testing

struct VerdictVerifierTests {
    let macID = UUID()
    let deviceID = UUID()
    let signer = SoftwareSigner()
    let now = Date.now

    func verifier() -> VerdictVerifier {
        var verifier = VerdictVerifier(macID: macID)
        verifier.trust(deviceID: deviceID, signingKey: signer.publicKey)
        return verifier
    }

    func signedVerdict(issuedAt: Date? = nil, macID: UUID? = nil) throws -> SignedVerdict {
        try Verdict(requestID: UUID(), answer: .allowForSession, macID: macID ?? self.macID, issuedAt: issuedAt ?? now)
            .signed(by: signer, deviceID: deviceID)
    }

    @Test func validVerdictPasses() throws {
        var verifier = verifier()
        let signed = try signedVerdict()
        #expect(try verifier.verify(signed, now: now) == signed.verdict)
    }

    @Test func repeatedNonceIsRefused() throws {
        var verifier = verifier()
        let signed = try signedVerdict()
        _ = try verifier.verify(signed, now: now)
        #expect(throws: VerdictRejection.repeatedNonce) {
            try verifier.verify(signed, now: now.addingTimeInterval(5))
        }
    }

    @Test(arguments: [Verdict.Answer.deny, .allowOnce])
    func everySignedFieldIsChecked(answer: Verdict.Answer) throws {
        var verifier = verifier()
        let signed = try signedVerdict()
        let original = signed.verdict
        let changes = [
            Verdict(requestID: UUID(), nonce: original.nonce, answer: original.answer, issuedAt: original.issuedAt, macID: macID),
            Verdict(requestID: original.requestID, nonce: Data(repeating: 7, count: 16), answer: original.answer, issuedAt: original.issuedAt, macID: macID),
            Verdict(requestID: original.requestID, nonce: original.nonce, answer: answer, issuedAt: original.issuedAt, macID: macID),
            Verdict(requestID: original.requestID, nonce: original.nonce, answer: original.answer, issuedAt: original.issuedAt.addingTimeInterval(-1), macID: macID),
        ]
        for verdict in changes {
            let forged = SignedVerdict(verdict: verdict, deviceID: deviceID, signature: signed.signature)
            #expect(throws: VerdictRejection.invalidSignature) {
                try verifier.verify(forged, now: now)
            }
        }
    }

    @Test func signatureByAnotherKeyIsRefused() throws {
        var verifier = verifier()
        let verdict = Verdict(requestID: UUID(), answer: .allowOnce, macID: macID, issuedAt: now)
        let forged = try verdict.signed(by: SoftwareSigner(), deviceID: deviceID)
        #expect(throws: VerdictRejection.invalidSignature) {
            try verifier.verify(forged, now: now)
        }
    }

    @Test func verdictForAnotherMacIsRefused() throws {
        var verifier = verifier()
        #expect(throws: VerdictRejection.otherMac) {
            try verifier.verify(signedVerdict(macID: UUID()), now: now)
        }
    }

    @Test func verdictOlderThanTenMinutesIsRefused() throws {
        var verifier = verifier()
        #expect(throws: VerdictRejection.expired) {
            try verifier.verify(signedVerdict(issuedAt: now.addingTimeInterval(-601)), now: now)
        }
        #expect(try verifier.verify(signedVerdict(issuedAt: now.addingTimeInterval(-599)), now: now).answer == .allowForSession)
    }

    @Test func verdictFromTheFutureIsRefused() throws {
        var verifier = verifier()
        #expect(throws: VerdictRejection.expired) {
            try verifier.verify(signedVerdict(issuedAt: now.addingTimeInterval(120)), now: now)
        }
    }

    @Test func unknownDeviceIsRefused() throws {
        var verifier = VerdictVerifier(macID: macID)
        #expect(throws: VerdictRejection.unknownDevice) {
            try verifier.verify(signedVerdict(), now: now)
        }
    }

    @Test func revokedDeviceIsRefused() throws {
        var verifier = verifier()
        verifier.revoke(deviceID: deviceID)
        #expect(throws: VerdictRejection.revokedDevice) {
            try verifier.verify(signedVerdict(), now: now)
        }
    }
}
