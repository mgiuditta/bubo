import CryptoKit
import DeliveryKit
import Foundation
import Testing

struct DeliveryCipherTests {
    let sender = Keys.alice
    let recipient = Keys.bob
    /// Three chunks, the last one short.
    let content = Data((0..<(2 * DeliveryCipher.chunkSize + 1234)).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    @Test func opensWhatItSeals() throws {
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        #expect(try DeliveryCipher.open(file, with: recipient, from: sender.publicKey) == content)
        let header = try DeliveryHeader(decoding: file)
        #expect(header == DeliveryHeader(kind: .consegna, recipient: KeyID(recipient.publicKey),
                                         sender: KeyID(sender.publicKey), contentSize: UInt64(content.count)))
    }

    @Test(arguments: [0, 1, DeliveryCipher.chunkSize - 1, DeliveryCipher.chunkSize, DeliveryCipher.chunkSize + 1])
    func opensEveryChunkBoundary(size: Int) throws {
        let content = Data(repeating: 42, count: size)
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        #expect(try DeliveryCipher.open(file, with: recipient, from: sender.publicKey) == content)
    }

    @Test func refusesAChangedHeader() throws {
        var file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        // The content size, one byte less: still a valid header with the same chunks.
        file[DeliveryHeader.byteCount - 1] &-= 1
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesAnAlteredByte() throws {
        var file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        file[file.count / 2] ^= 0x01
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesSwappedChunks() throws {
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        var chunks = Chunks(file)
        chunks.sealed.swapAt(0, 1)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(chunks.file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesARemovedChunk() throws {
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        var chunks = Chunks(file)
        chunks.sealed.remove(at: 1)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(chunks.file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesARemovedLastChunk() throws {
        // Two whole chunks: without the last, the file ends cleanly after a chunk.
        let content = Data(repeating: 7, count: 2 * DeliveryCipher.chunkSize)
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        var chunks = Chunks(file)
        chunks.sealed.removeLast()
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(chunks.file, with: recipient, from: sender.publicKey)
        }
        // Also with the header's size made to match: the first chunk was not sealed as the last.
        var shortened = chunks.file
        shortened.replaceSubrange(0..<DeliveryHeader.byteCount, with: {
            var header = try! DeliveryHeader(decoding: file)
            header.contentSize = UInt64(DeliveryCipher.chunkSize)
            return header.encoded
        }())
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(shortened, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesDataAfterTheLastChunk() throws {
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(file + Data([0]), with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesAnotherSendersKey() throws {
        let file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: Keys.carol)
        #expect(throws: DeliveryError.otherSender) {
            try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        }
        // Carol writing Alice's key identifier in the header: the authentication does not pass.
        var forged = file
        forged.replaceSubrange(14..<22, with: KeyID(sender.publicKey).bytes)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(forged, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesAnotherRecipient() throws {
        let file = try DeliveryCipher.seal(content, for: Keys.carol.publicKey, from: sender)
        #expect(throws: DeliveryError.otherRecipient) {
            try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesATicket() throws {
        let ticket = Ticket(person: "Alice", machine: "MacBook", publicKey: sender.publicKey)
        #expect(throws: DeliveryError.wrongKind) {
            try DeliveryCipher.open(ticket.encoded, with: recipient, from: sender.publicKey)
        }
    }

    @Test func refusesANewerFormat() throws {
        var file = try DeliveryCipher.seal(content, for: recipient.publicKey, from: sender)
        file[5] = 2
        #expect(throws: DeliveryError.unsupportedVersion(2)) {
            try DeliveryCipher.open(file, with: recipient, from: sender.publicKey)
        }
    }

    @Test func opensTheFixedVector() throws {
        let file = try #require(Data(hex: Vectors.sealedFile))
        #expect(try DeliveryCipher.open(file, with: recipient, from: sender.publicKey) == Data("Ciao da Bubo".utf8))
    }

    @Test func sealsAndOpensFiles() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "contenuto")
        let sealed = folder.appending(path: "consegna.bubo")
        let output = folder.appending(path: "aperto")
        try content.write(to: input)
        try DeliveryCipher.seal(contentsOf: input, to: sealed, for: recipient.publicKey, from: sender)
        #expect(try DeliveryHeader(contentsOf: sealed).contentSize == UInt64(content.count))
        try DeliveryCipher.open(contentsOf: sealed, to: output, with: recipient, from: sender.publicKey)
        #expect(try Data(contentsOf: output) == content)

        // A failed opening leaves nothing behind.
        var damaged = try Data(contentsOf: sealed)
        damaged[damaged.count - 1] ^= 0x01
        try damaged.write(to: sealed)
        #expect(throws: DeliveryError.damaged) {
            try DeliveryCipher.open(contentsOf: sealed, to: output, with: recipient, from: sender.publicKey)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

/// A sealed file cut into header, encapsulated key and sealed chunks, to rearrange them.
struct Chunks {
    var prefix: Data
    var sealed: [Data]

    init(_ file: Data) {
        let start = DeliveryHeader.byteCount + DeliveryCipher.encapsulatedKeyByteCount
        prefix = file.prefix(start)
        let size = DeliveryCipher.chunkSize + 16
        sealed = stride(from: start, to: file.count, by: size).map { Data(file[$0..<min($0 + size, file.count)]) }
    }

    var file: Data {
        sealed.reduce(prefix, +)
    }
}
