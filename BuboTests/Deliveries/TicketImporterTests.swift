@testable import Bubo
import CryptoKit
import DeliveryKit
import Foundation
import Testing

struct TicketImporterTests {
    let own = P256.KeyAgreement.PrivateKey().publicKey
    let aliceKey = P256.KeyAgreement.PrivateKey().publicKey
    let reinstalledKey = P256.KeyAgreement.PrivateKey().publicKey

    var alice: Ticket { Ticket(person: "Alice", machine: "MacBook di Alice", publicKey: aliceKey) }

    @Test func newTicketIsSavedOnlyWhenTheCodeMatches() {
        let review = TicketImporter.review(alice, among: [], ownKey: own)
        #expect(review == .new)
        #expect(TicketImporter.receiving(alice, review: review, in: []).isEmpty)
        #expect(TicketImporter.rejecting(alice, review: review, in: []).isEmpty)
        let saved = TicketImporter.confirming(alice, review: review, in: [])
        #expect(saved.count == 1)
        #expect(saved.first?.status == .verified)
        #expect(saved.first?.holds(aliceKey) == true)
    }

    @Test func sameTicketTwiceIsNoDuplicate() throws {
        let saved = TicketImporter.confirming(alice, review: .new, in: [])
        let id = try #require(saved.first?.id)
        let review = TicketImporter.review(alice, among: saved, ownKey: own)
        #expect(review == .alreadyVerified(id))
        #expect(TicketImporter.confirming(alice, review: review, in: saved) == saved)
    }

    @Test func otherKeyForTheSamePersonAndMacIsKeyChanged() throws {
        let saved = TicketImporter.confirming(alice, review: .new, in: [])
        let id = try #require(saved.first?.id)
        let reinstalled = Ticket(person: "Alice", machine: "MacBook di Alice", publicKey: reinstalledKey)
        let review = TicketImporter.review(reinstalled, among: saved, ownKey: own)
        #expect(review == .keyChanged(id))

        // Marked at once, not usable, the old key kept until Riverifica.
        let received = TicketImporter.receiving(reinstalled, review: review, in: saved)
        let changed = try #require(received.first)
        #expect(changed.status == .keyChanged)
        #expect(changed.holds(aliceKey))
        #expect(changed.replacement?.publicKey.x963Representation == reinstalledKey.x963Representation)
        // Opened again before Riverifica: still to verify, not a new row.
        #expect(TicketImporter.review(reinstalled, among: received, ownKey: own) == .keyChanged(id))
        #expect(TicketImporter.review(alice, among: received, ownKey: own) == .keyChanged(id))

        // Non coincide: still changed, without the new key.
        let rejected = try #require(TicketImporter.rejecting(reinstalled, review: review, in: received).first)
        #expect(rejected.status == .keyChanged)
        #expect(rejected.newKey == nil)

        // Coincide: the new key is the verified one.
        let confirmed = try #require(TicketImporter.confirming(reinstalled, review: review, in: received).first)
        #expect(confirmed.id == id)
        #expect(confirmed.status == .verified)
        #expect(confirmed.holds(reinstalledKey))
        #expect(confirmed.newKey == nil)
    }

    @Test func ownTicketIsNotImported() {
        let ownTicket = Ticket(person: "Io", machine: "Questo Mac", publicKey: own)
        #expect(TicketImporter.review(ownTicket, among: [], ownKey: own) == .own)
        #expect(TicketImporter.confirming(ownTicket, review: .own, in: []).isEmpty)
    }

    @Test func storeKeepsTheTickets() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(file: folder.appending(path: "Biglietti.json"))
        #expect(try store.tickets().isEmpty)
        let tickets = TicketImporter.confirming(alice, review: .new, in: [], at: Date(timeIntervalSince1970: 1_000_000))
        try store.save(tickets)
        #expect(try store.tickets() == tickets)
    }
}
