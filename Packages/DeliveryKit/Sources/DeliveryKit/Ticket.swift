import CryptoKit
import Foundation

/// A Biglietto: the public key of a Macchina, with the names of its person and Mac (spec 24).
///
/// A `.bubo` of kind ``DeliveryKind/biglietto``, not encrypted: the header, then the content as JSON. Anyone can
/// make one with any names; the ``VerificationCode`` read aloud is what makes it trustworthy.
public struct Ticket: Sendable {
    /// The person, from the macOS account's name unless changed.
    public var person: String
    /// The Mac, from the computer's name.
    public var machine: String
    /// The Macchina's key.
    public var publicKey: P256.KeyAgreement.PublicKey

    /// Creates the Biglietto of `publicKey`.
    public init(person: String, machine: String, publicKey: P256.KeyAgreement.PublicKey) {
        self.person = person
        self.machine = machine
        self.publicKey = publicKey
    }

    /// Reads a Biglietto file.
    ///
    /// - Throws: ``DeliveryError/wrongKind`` for a Consegna; ``DeliveryError/damaged`` when the content does not
    ///   match the header or does not decode; else as ``DeliveryHeader/init(decoding:)``.
    public init(decoding file: Data) throws(DeliveryError) {
        let header = try DeliveryHeader(decoding: file)
        guard header.kind == .biglietto else { throw .wrongKind }
        let content = file.dropFirst(DeliveryHeader.byteCount)
        guard UInt64(content.count) == header.contentSize,
              let fields = try? JSONDecoder().decode(Fields.self, from: content),
              fields.version == 1,
              let key = try? P256.KeyAgreement.PublicKey(x963Representation: fields.publicKey),
              KeyID(key) == header.sender
        else { throw .damaged }
        person = fields.person
        machine = fields.machine
        publicKey = key
    }

    /// The identifier of the Biglietto's key.
    public var keyID: KeyID {
        KeyID(publicKey)
    }

    /// The whole Biglietto file.
    public var encoded: Data {
        let fields = Fields(version: 1, person: person, machine: machine, publicKey: publicKey.x963Representation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain strings and data does not fail.
        let content = (try? encoder.encode(fields)) ?? Data()
        let header = DeliveryHeader(kind: .biglietto, recipient: .none, sender: keyID, contentSize: UInt64(content.count))
        return header.encoded + content
    }

    /// The JSON content after the header.
    private struct Fields: Codable {
        var version: Int
        var person: String
        var machine: String
        var publicKey: Data
    }
}
