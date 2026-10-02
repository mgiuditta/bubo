import CryptoKit
import Foundation

/// The iPhone's answer to a permission Request, signed in the Secure Enclave (spec 21).
public struct Verdict: Codable, Sendable, Equatable {
    /// The answers the iPhone can give; "Sempre in questo Progetto" exists only on the Mac.
    public enum Answer: String, Codable, Sendable, CaseIterable {
        /// No.
        case deny
        /// Solo ora.
        case allowOnce
        /// Per questa Sessione.
        case allowForSession
    }

    /// The Request being answered.
    public let requestID: UUID
    /// 16 random bytes: the Mac refuses a nonce it has already seen.
    public let nonce: Data
    /// The answer.
    public let answer: Answer
    /// When the iPhone signed it; older than 10 minutes, it is refused.
    public let issuedAt: Date
    /// The Mac the Verdict is for.
    public let macID: UUID

    /// Creates a Verdict with a fresh random nonce.
    public init(requestID: UUID, answer: Answer, macID: UUID, issuedAt: Date = .now) {
        self.init(requestID: requestID, nonce: .random(count: 16), answer: answer, issuedAt: issuedAt, macID: macID)
    }

    /// Creates a Verdict with the given nonce.
    public init(requestID: UUID, nonce: Data, answer: Answer, issuedAt: Date, macID: UUID) {
        self.requestID = requestID
        self.nonce = nonce
        self.answer = answer
        self.issuedAt = issuedAt
        self.macID = macID
    }

    /// The signed bytes: `requestID ‖ nonce ‖ answer ‖ timestamp ‖ macID`, each with its length.
    var signedMessage: Data {
        var message = Data("bubo-remote/v1/verdict".utf8)
        message.appendField(requestID.bytes)
        message.appendField(nonce)
        message.appendField(Data(answer.rawValue.utf8))
        let milliseconds = Int64((issuedAt.timeIntervalSince1970 * 1000).rounded())
        message.appendField(withUnsafeBytes(of: milliseconds.bigEndian) { Data($0) })
        message.appendField(macID.bytes)
        return message
    }

    /// Returns the Verdict signed by `signer`, the key of the iPhone `deviceID`.
    public func signed(by signer: some RemoteSigner, deviceID: UUID) throws -> SignedVerdict {
        SignedVerdict(verdict: self, deviceID: deviceID, signature: try signer.signature(for: signedMessage).derRepresentation)
    }
}

/// A Verdict with the iPhone that signed it and the DER signature.
public struct SignedVerdict: Codable, Sendable, Equatable {
    /// The Verdict.
    public let verdict: Verdict
    /// The paired iPhone that signed it.
    public let deviceID: UUID
    /// The DER-encoded ECDSA signature of ``Verdict/signedMessage``.
    public let signature: Data

    /// Creates a signed Verdict from its parts.
    public init(verdict: Verdict, deviceID: UUID, signature: Data) {
        self.verdict = verdict
        self.deviceID = deviceID
        self.signature = signature
    }
}
