import CryptoKit
import DeliveryKit
import Foundation
import Security

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

    /// The identifier of the verified key; `nil` when the key does not decode.
    var keyIdentifier: KeyID? {
        (try? P256.KeyAgreement.PublicKey(x963Representation: publicKey)).map(KeyID.init)
    }

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

/// The Biglietti received, with the identifier of this Macchina's key, in the folder Bubo shares with its Quick Look
/// extension. They hold public keys only: no keychain.
nonisolated struct TicketStore: Sendable {
    /// The JSON file, `[ReceivedTicket]`.
    let file: URL

    /// The store in the shared folder, the same for Bubo and its Quick Look extension.
    static let standard = TicketStore(file: sharedFolder.appending(path: "Biglietti.json"))

    /// Where Bubo kept the Biglietti before the App Group.
    static let legacyFile = URL.applicationSupportDirectory.appending(path: "Bubo/Biglietti.json")

    /// The container of the App Group in the running executable's entitlements, which Bubo and its Quick Look
    /// extension share; Bubo's Application Support folder in a build signed without it.
    static var sharedFolder: URL {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString,
                                                          nil) as? [String],
              let group = groups.first,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return URL.applicationSupportDirectory.appending(path: "Bubo", directoryHint: .isDirectory) }
        return container
    }

    /// The file with the 8 bytes of the identifier of this Macchina's key, next to the Biglietti.
    var ownKeyFile: URL {
        file.deletingLastPathComponent().appending(path: "ChiaveMacchina")
    }

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

    /// The identifier of this Macchina's key, as Bubo last saved it; `nil` before that or when unreadable.
    func ownKeyID() -> KeyID? {
        (try? Data(contentsOf: ownKeyFile)).flatMap(KeyID.init(bytes:))
    }

    /// Saves the identifier of this Macchina's key, for Quick Look to tell the Consegne meant for this Mac.
    func saveOwnKeyID(_ id: KeyID) throws {
        try FileManager.default.createDirectory(at: ownKeyFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try id.bytes.write(to: ownKeyFile, options: [.atomic])
    }

    /// Moves the Biglietti from `legacy`, where an older Bubo kept them, when this store has none yet.
    func adoptLegacyFile(at legacy: URL) throws {
        let manager = FileManager.default
        guard legacy.standardizedFileURL != file.standardizedFileURL,
              manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: file.path)
        else { return }
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: legacy, to: file)
    }
}
