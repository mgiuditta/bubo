import CryptoKit
import DeliveryKit
import Foundation
import os
import UniformTypeIdentifiers

/// Impostazioni › Consegne and the opening of `.bubo` files: this Macchina's key and Biglietto, the Biglietti
/// received, and the import of a Biglietto with its code (spec 24).
@Observable
final class DeliveriesController {
    /// A Biglietto opened, waiting for the user to compare its code.
    struct TicketImport: Identifiable {
        let id = UUID()
        let ticket: Ticket
        let review: TicketImporter.Review
        /// The code of this Mac and the Biglietto's, the same on the other Mac.
        let code: VerificationCode
        /// Coincide was pressed: the sheet proposes to send this Mac's Biglietto back.
        var isConfirmed = false
    }

    /// What opening a `.bubo` file led to.
    enum Opening: Equatable {
        /// A Biglietto, now in ``pendingImport``.
        case ticket
        /// A Consegna: opened in a later version (#278).
        case consegna
        /// The file does not open.
        case failed(DeliveryError)
    }

    /// `UserDefaults` key of the person's name on this Mac's Biglietto, when changed.
    static let personKey = "deliveriesPerson"

    /// This Macchina's public key, once loaded.
    private(set) var ownKey: P256.KeyAgreement.PublicKey?
    /// The Biglietti received, oldest first.
    private(set) var tickets: [ReceivedTicket] = []
    /// The Biglietto opened and not decided yet.
    var pendingImport: TicketImport?
    /// The last failure of the key or of the store, shown in Impostazioni › Consegne.
    private(set) var failure: String?
    /// This Mac's Biglietto as a file, to share; rewritten when the person's name changes.
    private(set) var ownTicketFile: URL?
    /// The person on this Mac's Biglietto: the macOS account's name unless changed.
    var person: String {
        didSet {
            defaults.set(person, forKey: Self.personKey)
            writeOwnTicket()
        }
    }
    /// The Mac on this Mac's Biglietto: the computer's name.
    let machine: String
    /// The notice of each Sessione delivered since Bubo started: "Consegnata con ‹canale› a ‹nome›…".
    private(set) var deliveredNotices: [Session.ID: String] = [:]

    private let key: MachineKey
    private let store: TicketStore
    private let defaults: UserDefaults
    /// Where this Mac's Biglietto is written to be shared.
    private let folder: URL
    private let log = Logger(subsystem: "com.mgiuditta.bubo", category: "deliveries")

    init(key: MachineKey, store: TicketStore, machine: String, folder: URL, defaults: UserDefaults = .standard) {
        self.key = key
        self.store = store
        self.machine = machine
        self.folder = folder
        self.defaults = defaults
        person = defaults.string(forKey: Self.personKey) ?? NSFullUserName()
    }

    /// The controller of this Mac: key in the Secure Enclave, Biglietti in Application Support.
    static func live() -> DeliveriesController {
        DeliveriesController(key: .live, store: .standard, machine: Host.current().localizedName ?? "Mac",
                             folder: URL.temporaryDirectory.appending(path: "Biglietti"))
    }

    /// Loads the key, created the first time, and the Biglietti; writes this Mac's Biglietto to share.
    func load() async {
        loadTickets()
        guard ownKey == nil else { return }
        do {
            ownKey = try await key.privateKey().publicKey
            writeOwnTicket()
        } catch .noSecureEnclave {
            failure = String(localized: "Questo Mac non ha il Secure Enclave: non può mandare né ricevere Consegne.")
        } catch {
            log.error("Machine key unavailable: \(String(describing: error), privacy: .public)")
            failure = String(localized: "La chiave di questo Mac non si apre. Sblocca il Mac e riapri le Impostazioni.")
        }
    }

    /// Opens the `.bubo` file at `url`: a Biglietto goes to ``pendingImport`` to compare its code.
    func open(_ url: URL) async -> Opening {
        do {
            let header = try DeliveryHeader(contentsOf: url)
            guard header.kind == .biglietto else { return .consegna }
            let file: Data
            do {
                file = try Data(contentsOf: url)
            } catch {
                throw DeliveryError.unreadable
            }
            let ticket = try Ticket(decoding: file)
            await load()
            guard let ownKey else { return .failed(.unreadable) }
            let review = TicketImporter.review(ticket, among: tickets, ownKey: ownKey)
            save(TicketImporter.receiving(ticket, review: review, in: tickets))
            pendingImport = TicketImport(ticket: ticket, review: review, code: VerificationCode(ownKey, ticket.publicKey))
            return .ticket
        } catch let error as DeliveryError {
            log.error("Bubo file not opened: \(String(describing: error), privacy: .public)")
            return .failed(error)
        } catch {
            return .failed(.unreadable)
        }
    }

    /// Coincide: saves the Biglietto as verified, then the sheet proposes to send this Mac's one.
    func confirm() {
        guard let pending = pendingImport else { return }
        save(TicketImporter.confirming(pending.ticket, review: pending.review, in: tickets))
        pendingImport?.isConfirmed = true
    }

    /// Non coincide: discards the Biglietto.
    func reject() {
        guard let pending = pendingImport else { return }
        save(TicketImporter.rejecting(pending.ticket, review: pending.review, in: tickets))
        pendingImport = nil
    }

    /// Rimuovi: forgets `ticket`; Consegne no longer go to or come from that Macchina.
    func remove(_ ticket: ReceivedTicket) {
        save(tickets.filter { $0.id != ticket.id })
    }

    /// Riverifica: the import sheet again, with the new key of a Biglietto marked `chiave cambiata`.
    func reverify(_ ticket: ReceivedTicket) {
        guard let replacement = ticket.replacement, let ownKey else { return }
        pendingImport = TicketImport(ticket: replacement, review: .keyChanged(ticket.id),
                                     code: VerificationCode(ownKey, replacement.publicKey))
    }

    /// This Macchina's key, which seals the Consegne it sends.
    ///
    /// - Throws: ``MachineKey/Failure``.
    func sealingKey() async throws(MachineKey.Failure) -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        try await key.privateKey()
    }

    /// Notes that the Sessione `id` went through `channel` to `ticket`'s Macchina: the notice in the Sessione.
    func noteDelivery(of id: Session.ID, through channel: String, to ticket: ReceivedTicket) {
        deliveredNotices[id] = String(localized: "Consegnata con \(channel) a \(ticket.person) · \(ticket.machine). La Sessione resta tua; da qui in poi le due copie vanno ognuna per conto suo.")
    }

    /// Hides the notice of the Sessione `id`.
    func dismissDeliveryNotice(of id: Session.ID) {
        deliveredNotices[id] = nil
    }

    /// The code of this Mac and `ticket`'s verified key.
    func code(of ticket: ReceivedTicket) -> VerificationCode? {
        guard let ownKey, let key = try? P256.KeyAgreement.PublicKey(x963Representation: ticket.publicKey) else {
            return nil
        }
        return VerificationCode(ownKey, key)
    }

    private func loadTickets() {
        do {
            tickets = try store.tickets()
        } catch {
            log.error("Biglietti unreadable: \(error)")
            failure = String(localized: "I Biglietti ricevuti non si leggono.")
        }
    }

    private func save(_ tickets: [ReceivedTicket]) {
        do {
            try store.save(tickets)
            self.tickets = tickets
        } catch {
            log.error("Biglietti not saved: \(error)")
            failure = String(localized: "I Biglietti non si salvano. Riprova.")
        }
    }

    private func writeOwnTicket() {
        guard let ownKey else { return }
        let ticket = Ticket(person: person, machine: machine, publicKey: ownKey)
        let name = String(localized: "Biglietto di \(person)").replacing("/", with: "-")
        let file = folder.appending(path: name).appendingPathExtension(for: .buboFile)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let ownTicketFile, ownTicketFile != file { try? FileManager.default.removeItem(at: ownTicketFile) }
            try ticket.encoded.write(to: file, options: .atomic)
            ownTicketFile = file
        } catch {
            log.error("Own Biglietto not written: \(error)")
            ownTicketFile = nil
        }
    }
}

extension UTType {
    /// A `.bubo` file: a Consegna or a Biglietto (spec 24).
    nonisolated static let buboFile = UTType(exportedAs: "com.mgiuditta.bubo.consegna")
}
