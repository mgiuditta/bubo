import DeliveryKit
import Foundation

/// What Quick Look shows of a `.bubo` file without opening it (spec 24, Destinatario): the header in the clear, the
/// names of a Biglietto, and who the Biglietti received say is on either end of a Consegna.
///
/// Compiled into Bubo and into its Quick Look extension, which reads it from the shared ``TicketStore``.
nonisolated enum BuboFileSummary: Equatable, Sendable {
    /// Who sent a Consegna.
    enum Sender: Equatable, Sendable {
        /// A verified Biglietto has the sender's key.
        case known(person: String, machine: String)
        /// No verified Biglietto has the sender's key: Bubo will not open it.
        case unknown
    }

    /// Who a Consegna is encrypted for.
    enum Recipient: Equatable, Sendable {
        /// This Macchina.
        case thisMachine
        /// Another Macchina: its name when a Biglietto received has its key.
        case otherMachine(String?)
        /// This Macchina's key is not known yet: Bubo has not saved it.
        case undetermined
    }

    /// A Consegna, encrypted: who sent it, who it is for, and the size of its content.
    case consegna(sender: Sender, recipient: Recipient, size: UInt64)
    /// A Biglietto, in the clear: its names and the identifier of its key.
    case biglietto(person: String, machine: String, key: KeyID)

    /// The largest Biglietto read, in bytes: a real one is a few hundred bytes.
    static let maximumTicketSize: UInt64 = 64 * 1024

    /// Reads the summary of the `.bubo` at `url`, with the Biglietti received and this Macchina's key identifier.
    ///
    /// Of a Consegna it reads the header only.
    ///
    /// - Throws: ``DeliveryError``, as ``DeliveryHeader/init(contentsOf:)`` and ``Ticket/init(decoding:)``; a
    ///   Biglietto larger than ``maximumTicketSize`` is ``DeliveryError/damaged``.
    init(contentsOf url: URL, tickets: [ReceivedTicket], ownKey: KeyID?) throws(DeliveryError) {
        let header = try DeliveryHeader(contentsOf: url)
        switch header.kind {
        case .consegna:
            self = Self(consegna: header, tickets: tickets, ownKey: ownKey)
        case .biglietto:
            guard header.contentSize <= Self.maximumTicketSize else { throw .damaged }
            let file: Data
            do {
                file = try Data(contentsOf: url)
            } catch {
                throw .unreadable
            }
            let ticket = try Ticket(decoding: file)
            self = .biglietto(person: ticket.person, machine: ticket.machine, key: ticket.keyID)
        }
    }

    /// The summary of the Consegna with `header`: the sender as Bubo would check it, before decrypting.
    init(consegna header: DeliveryHeader, tickets: [ReceivedTicket], ownKey: KeyID?) {
        let sender: Sender = if let known = tickets.first(where: { $0.keyIdentifier == header.sender }),
                                known.status == .verified {
            .known(person: known.person, machine: known.machine)
        } else {
            .unknown
        }
        let recipient: Recipient = switch ownKey {
        case .some(header.recipient): .thisMachine
        case nil: .undetermined
        default: .otherMachine(tickets.first { $0.keyIdentifier == header.recipient }?.machine)
        }
        self = .consegna(sender: sender, recipient: recipient, size: header.contentSize)
    }
}
