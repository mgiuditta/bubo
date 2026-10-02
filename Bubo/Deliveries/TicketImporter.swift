import CryptoKit
import DeliveryKit
import Foundation

/// What opening a Biglietto does to the Biglietti received (spec 24, Biglietto): pure, the caller saves the result.
///
/// A new Biglietto is saved only when the user says the code matches. One with the same Persona · Macchina as a saved
/// one but another key marks the saved one `chiave cambiata` at once, keeping the new key aside until Riverifica.
nonisolated enum TicketImporter {
    /// How a Biglietto relates to the ones received.
    enum Review: Equatable, Sendable {
        /// Never seen: to verify.
        case new
        /// Already received and verified with this key: nothing to do.
        case alreadyVerified(ReceivedTicket.ID)
        /// The same Persona · Macchina as `id`, with another key, or a key not verified again yet: to verify again.
        case keyChanged(ReceivedTicket.ID)
        /// This Mac's own Biglietto.
        case own
    }

    /// How `ticket` relates to `tickets`, on the Mac whose key is `ownKey`.
    static func review(_ ticket: Ticket, among tickets: [ReceivedTicket], ownKey: P256.KeyAgreement.PublicKey) -> Review {
        let key = ticket.publicKey.x963Representation
        if key == ownKey.x963Representation { return .own }
        if let saved = tickets.first(where: { $0.publicKey == key || $0.newKey == key }) {
            return saved.status == .verified && saved.publicKey == key ? .alreadyVerified(saved.id) : .keyChanged(saved.id)
        }
        if let saved = tickets.first(where: { $0.person == ticket.person && $0.machine == ticket.machine }) {
            return .keyChanged(saved.id)
        }
        return .new
    }

    /// The Biglietti once `ticket` is opened: a changed key marks its Biglietto at once.
    static func receiving(_ ticket: Ticket, review: Review, in tickets: [ReceivedTicket]) -> [ReceivedTicket] {
        guard case .keyChanged(let id) = review else { return tickets }
        return tickets.map { saved in
            guard saved.id == id else { return saved }
            var changed = saved
            changed.status = .keyChanged
            changed.newKey = ticket.publicKey.x963Representation
            return changed
        }
    }

    /// The Biglietti once the user says the code of `ticket` matches (Coincide): saved, or its new key verified.
    static func confirming(_ ticket: Ticket, review: Review, in tickets: [ReceivedTicket],
                           at date: Date = .now) -> [ReceivedTicket] {
        switch review {
        case .new:
            return tickets + [ReceivedTicket(id: UUID(), person: ticket.person, machine: ticket.machine,
                                             publicKey: ticket.publicKey.x963Representation, status: .verified,
                                             verifiedAt: date)]
        case .keyChanged(let id):
            return tickets.map { saved in
                guard saved.id == id else { return saved }
                return ReceivedTicket(id: id, person: ticket.person, machine: ticket.machine,
                                      publicKey: ticket.publicKey.x963Representation, status: .verified,
                                      verifiedAt: date)
            }
        case .alreadyVerified, .own:
            return tickets
        }
    }

    /// The Biglietti once the user says the code of `ticket` does not match (Non coincide): `ticket` is discarded,
    /// and a changed Biglietto stays `chiave cambiata`, without the new key.
    static func rejecting(_ ticket: Ticket, review: Review, in tickets: [ReceivedTicket]) -> [ReceivedTicket] {
        guard case .keyChanged(let id) = review else { return tickets }
        return tickets.map { saved in
            guard saved.id == id, saved.newKey == ticket.publicKey.x963Representation else { return saved }
            var changed = saved
            changed.newKey = nil
            return changed
        }
    }
}
