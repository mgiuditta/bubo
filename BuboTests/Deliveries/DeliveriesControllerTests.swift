@testable import Bubo
import CryptoKit
import DeliveryKit
import Foundation
import Testing

/// The key's reference in memory: the keychain is not reachable from the test host (-34018).
actor InMemoryMachineKeyStorage: MachineKeyStorage {
    private(set) var saved: Data?

    func reference() -> Data? { saved }

    func save(_ reference: Data) { saved = reference }
}

/// The controller with the key in the Secure Enclave and the rest in a temporary folder.
@Suite(.enabled(if: MachineKey.isSecureEnclaveAvailable, "No Secure Enclave on this Mac"))
struct DeliveriesControllerTests {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let storage = InMemoryMachineKeyStorage()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

    func makeController() -> DeliveriesController {
        DeliveriesController(key: MachineKey(storage: storage), store: TicketStore(file: folder.appending(path: "Biglietti.json")),
                             machine: "Mac di prova", folder: folder.appending(path: "Il mio"), defaults: defaults)
    }

    @Test func keyIsCreatedOnceInTheSecureEnclave() async throws {
        let key = MachineKey(storage: storage)
        let first = try await key.privateKey()
        let reference = try #require(await storage.saved)
        let second = try await key.privateKey()
        #expect(second.publicKey.x963Representation == first.publicKey.x963Representation)
        #expect(await storage.saved == reference)
    }

    @Test func ownTicketCarriesTheMachineKey() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = makeController()
        controller.person = "Matteo"
        await controller.load()
        let file = try #require(controller.ownTicketFile)
        let ticket = try Ticket(decoding: Data(contentsOf: file))
        #expect(ticket.person == "Matteo")
        #expect(ticket.machine == "Mac di prova")
        #expect(ticket.publicKey.x963Representation == controller.ownKey?.x963Representation)
    }

    @Test func openedTicketWaitsForTheCode() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = makeController()
        let alice = Ticket(person: "Alice", machine: "MacBook", publicKey: P256.KeyAgreement.PrivateKey().publicKey)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Biglietto di Alice.bubo")
        try alice.encoded.write(to: file)

        #expect(await controller.open(file) == .ticket)
        let pending = try #require(controller.pendingImport)
        #expect(pending.review == .new)
        #expect(pending.code == VerificationCode(try #require(controller.ownKey), alice.publicKey))
        #expect(controller.tickets.isEmpty)

        controller.confirm()
        #expect(controller.pendingImport?.isConfirmed == true)
        #expect(controller.tickets.map(\.status) == [.verified])
        // Saved on disk, read back by a new controller.
        let reopened = makeController()
        await reopened.load()
        // The dates are kept to the second.
        #expect(reopened.tickets.map(\.id) == controller.tickets.map(\.id))
        #expect(reopened.tickets.map(\.publicKey) == controller.tickets.map(\.publicKey))
    }

    @Test func consegnaAndForeignFilesDoNotImport() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controller = makeController()
        let consegna = folder.appending(path: "consegna.bubo")
        let recipient = P256.KeyAgreement.PrivateKey()
        try DeliveryCipher.seal(Data("x".utf8), for: recipient.publicKey, from: P256.KeyAgreement.PrivateKey())
            .write(to: consegna)
        #expect(await controller.open(consegna) == .consegna)
        let foreign = folder.appending(path: "altro.bubo")
        try Data("non è un Biglietto".utf8).write(to: foreign)
        #expect(await controller.open(foreign) == .failed(.notBubo))
        #expect(controller.pendingImport == nil)
    }
}
