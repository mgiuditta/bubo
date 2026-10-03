import CryptoKit
import DeliveryKit
import Foundation
import Testing
@testable import Bubo

/// What Quick Look shows of a `.bubo`: sender and recipient from the header and the Biglietti, the names of a
/// Biglietto, and the identifier of this Macchina's key shared with the extension.
struct BuboFileSummaryTests {
    let folder: URL
    let ownKey = KeyID(P256.KeyAgreement.PrivateKey().publicKey)
    let senderKey = P256.KeyAgreement.PrivateKey().publicKey

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "BuboFileSummaryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func ticket(_ key: P256.KeyAgreement.PublicKey, machine: String = "MacBook di Ada",
                status: ReceivedTicket.Status = .verified) -> ReceivedTicket {
        ReceivedTicket(id: UUID(), person: "Ada", machine: machine, publicKey: key.x963Representation,
                       status: status, verifiedAt: .now)
    }

    func header(to recipient: KeyID) -> DeliveryHeader {
        DeliveryHeader(kind: .consegna, recipient: recipient, sender: KeyID(senderKey), contentSize: 2_048)
    }

    @Test func verifiedSenderToThisMachine() {
        let summary = BuboFileSummary(consegna: header(to: ownKey), tickets: [ticket(senderKey)], ownKey: ownKey)
        #expect(summary == .consegna(sender: .known(person: "Ada", machine: "MacBook di Ada"),
                                     recipient: .thisMachine, size: 2_048))
    }

    @Test(arguments: [false, true])
    func senderWithoutVerifiedTicketIsUnknown(hasChangedTicket: Bool) {
        let tickets = hasChangedTicket ? [ticket(senderKey, status: .keyChanged)] : []
        let summary = BuboFileSummary(consegna: header(to: ownKey), tickets: tickets, ownKey: ownKey)
        #expect(summary == .consegna(sender: .unknown, recipient: .thisMachine, size: 2_048))
    }

    @Test func otherMachineIsNamedWhenATicketHasItsKey() {
        let other = P256.KeyAgreement.PrivateKey().publicKey
        let tickets = [ticket(senderKey), ticket(other, machine: "iMac di Bruno")]
        let named = BuboFileSummary(consegna: header(to: KeyID(other)), tickets: tickets, ownKey: ownKey)
        let unnamed = BuboFileSummary(consegna: header(to: KeyID(P256.KeyAgreement.PrivateKey().publicKey)),
                                      tickets: tickets, ownKey: ownKey)
        #expect(named == .consegna(sender: .known(person: "Ada", machine: "MacBook di Ada"),
                                   recipient: .otherMachine("iMac di Bruno"), size: 2_048))
        #expect(unnamed == .consegna(sender: .known(person: "Ada", machine: "MacBook di Ada"),
                                     recipient: .otherMachine(nil), size: 2_048))
    }

    @Test func recipientIsUndeterminedWithoutOwnKey() {
        let summary = BuboFileSummary(consegna: header(to: ownKey), tickets: [], ownKey: nil)
        #expect(summary == .consegna(sender: .unknown, recipient: .undetermined, size: 2_048))
    }

    @Test func consegnaFileIsReadFromItsHeader() throws {
        let file = folder.appending(path: "Consegna.bubo")
        try (header(to: ownKey).encoded + Data(repeating: 7, count: 64)).write(to: file)
        let summary = try BuboFileSummary(contentsOf: file, tickets: [], ownKey: ownKey)
        #expect(summary == .consegna(sender: .unknown, recipient: .thisMachine, size: 2_048))
    }

    @Test func ticketFileShowsItsNamesAndKey() throws {
        let file = folder.appending(path: "Biglietto.bubo")
        try Ticket(person: "Ada", machine: "MacBook di Ada", publicKey: senderKey).encoded.write(to: file)
        let summary = try BuboFileSummary(contentsOf: file, tickets: [], ownKey: nil)
        #expect(summary == .biglietto(person: "Ada", machine: "MacBook di Ada", key: KeyID(senderKey)))
    }

    @Test func oversizedTicketIsNotRead() throws {
        let file = folder.appending(path: "Grande.bubo")
        let header = DeliveryHeader(kind: .biglietto, recipient: .none, sender: KeyID(senderKey),
                                    contentSize: BuboFileSummary.maximumTicketSize + 1)
        try header.encoded.write(to: file)
        #expect(throws: DeliveryError.damaged) {
            try BuboFileSummary(contentsOf: file, tickets: [], ownKey: nil)
        }
    }

    @Test func ownKeyIdentifierIsSharedNextToTheTickets() throws {
        let store = TicketStore(file: folder.appending(path: "Biglietti.json"))
        #expect(store.ownKeyID() == nil)
        try store.saveOwnKeyID(ownKey)
        #expect(store.ownKeyID() == ownKey)
    }

    @Test func legacyTicketsMoveToTheSharedFolder() throws {
        let legacy = folder.appending(path: "Vecchio/Biglietti.json")
        try TicketStore(file: legacy).save([ticket(senderKey)])
        let store = TicketStore(file: folder.appending(path: "Gruppo/Biglietti.json"))
        try store.adoptLegacyFile(at: legacy)
        #expect(try store.tickets().map(\.machine) == ["MacBook di Ada"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func sharedTicketsAreNotReplacedByLegacyOnes() throws {
        let legacy = folder.appending(path: "Vecchio/Biglietti.json")
        try TicketStore(file: legacy).save([ticket(senderKey)])
        let store = TicketStore(file: folder.appending(path: "Gruppo/Biglietti.json"))
        try store.save([])
        try store.adoptLegacyFile(at: legacy)
        #expect(try store.tickets().isEmpty)
    }
}
