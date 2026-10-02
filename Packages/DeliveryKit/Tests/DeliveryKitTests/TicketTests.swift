import CryptoKit
import DeliveryKit
import Foundation
import Testing

struct TicketTests {
    @Test func keyIDsMatchTheVectors() {
        #expect(KeyID(Keys.alice.publicKey).description == Vectors.aliceKeyID)
        #expect(KeyID(Keys.bob.publicKey).description == Vectors.bobKeyID)
    }

    @Test func headerMatchesTheVector() throws {
        let header = DeliveryHeader(kind: .consegna, recipient: KeyID(Keys.bob.publicKey),
                                    sender: KeyID(Keys.alice.publicKey), contentSize: 0x0102_0304_0506)
        #expect(header.encoded.hex == Vectors.header)
        #expect(try DeliveryHeader(decoding: header.encoded) == header)
    }

    @Test func foreignFileIsNotBubo() {
        #expect(throws: DeliveryError.notBubo) { try DeliveryHeader(decoding: Data("%PDF-1.7 not a bubo file".utf8)) }
        #expect(throws: DeliveryError.notBubo) { try DeliveryHeader(decoding: Data("BUBO".utf8)) }
    }

    @Test func verificationCodeIsTheSameInEitherOrder() {
        let code = VerificationCode(Keys.alice.publicKey, Keys.bob.publicKey)
        #expect(code == VerificationCode(Keys.bob.publicKey, Keys.alice.publicKey))
        #expect(code.digits == Vectors.aliceBobCode)
        #expect(code.groups.count == 3 && code.groups.allSatisfy { $0.count == 4 })
        #expect(code.description == code.groups.joined(separator: " "))
        #expect(code != VerificationCode(Keys.alice.publicKey, Keys.carol.publicKey))
    }

    @Test func ticketRoundTrips() throws {
        let ticket = Ticket(person: "Alice Rossi", machine: "MacBook di Alice", publicKey: Keys.alice.publicKey)
        let read = try Ticket(decoding: ticket.encoded)
        #expect(read.person == "Alice Rossi")
        #expect(read.machine == "MacBook di Alice")
        #expect(read.keyID == ticket.keyID)
        let header = try DeliveryHeader(decoding: ticket.encoded)
        #expect(header.kind == .biglietto)
        #expect(header.recipient == .none)
        #expect(header.sender == KeyID(Keys.alice.publicKey))
    }

    @Test func ticketWithAnotherKeyIsDamaged() throws {
        let ticket = Ticket(person: "Alice", machine: "MacBook", publicKey: Keys.alice.publicKey)
        var file = ticket.encoded
        // The header names Bob's key, the content carries Alice's.
        file.replaceSubrange(14..<22, with: KeyID(Keys.bob.publicKey).bytes)
        #expect(throws: DeliveryError.damaged) { try Ticket(decoding: file) }
        #expect(throws: DeliveryError.damaged) { try Ticket(decoding: ticket.encoded.dropLast()) }
    }

    @Test func consegnaIsNotATicket() throws {
        let file = try DeliveryCipher.seal(Data("x".utf8), for: Keys.bob.publicKey, from: Keys.alice)
        #expect(throws: DeliveryError.wrongKind) { try Ticket(decoding: file) }
    }
}
