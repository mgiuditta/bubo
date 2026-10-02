import CryptoKit
import DeliveryKit
import Foundation

/// A Biglietto received and verified: the key of another Macchina that Consegne can go to and come from (spec 24).
nonisolated struct ReceivedTicket: Codable, Identifiable, Equatable, Sendable {
    /// Whether Consegne can use the Biglietto.
    enum Status: String, Codable, Sendable {
        /// The code matched: usable.
        case verified
        /// A Biglietto with the same Persona · Macchina came with another key: not usable until Riverifica.
        case keyChanged
    }

    let id: UUID
    var person: String
    var machine: String
    /// The verified key, x9.63.
    var publicKey: Data
    var status: Status
    var verifiedAt: Date
    /// The other key of the Biglietto that changed it, x9.63, until Riverifica compares its code.
    var newKey: Data?

    /// Whether `key` is the verified key of this Biglietto.
    func holds(_ key: P256.KeyAgreement.PublicKey) -> Bool {
        publicKey == key.x963Representation
    }

    /// The Biglietto with the new key, to verify again; `nil` without a new key.
    var replacement: Ticket? {
        guard let newKey, let key = try? P256.KeyAgreement.PublicKey(x963Representation: newKey) else { return nil }
        return Ticket(person: person, machine: machine, publicKey: key)
    }
}

/// The Biglietti received, in Bubo's Application Support folder. They hold public keys only: no keychain.
nonisolated struct TicketStore: Sendable {
    /// The JSON file, `[ReceivedTicket]`.
    let file: URL

    /// The store in Bubo's Application Support folder.
    static let standard = TicketStore(file: URL.applicationSupportDirectory.appending(path: "Bubo/Biglietti.json"))

    /// The Biglietti, oldest first; none when the file does not exist yet.
    ///
    /// - Throws: A file or decoding error; an unreadable file is never overwritten by ``save(_:)`` callers.
    func tickets() throws -> [ReceivedTicket] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ReceivedTicket].self, from: data)
    }

    /// Saves `tickets`, replacing the file.
    func save(_ tickets: [ReceivedTicket]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tickets).write(to: file, options: [.atomic])
    }
}
