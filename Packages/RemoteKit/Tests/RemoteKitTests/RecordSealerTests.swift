import CryptoKit
import Foundation
import RemoteKit
import Testing

struct RecordSealerTests {
    let sealer = RecordSealer(key: SymmetricKey(size: .bits256))

    @Test func sealedPayloadOpens() throws {
        let sealed = try sealer.seal(["titolo": "Rifattorizza il router"], recordID: "card-1")
        let opened = try sealer.open([String: String].self, from: sealed, recordID: "card-1")
        #expect(opened == ["titolo": "Rifattorizza il router"])
    }

    @Test func plaintextDoesNotAppearInThePayload() throws {
        let sealed = try sealer.seal(Data("rm -rf /Users/matteo/progetto".utf8), recordID: "request-1")
        #expect(sealed.range(of: Data("progetto".utf8)) == nil)
    }

    @Test func wrongAssociatedDataIsRefused() throws {
        let sealed = try sealer.seal(Data("ciao".utf8), recordID: "request-1")
        #expect(throws: RecordSealer.Failure.unreadable) {
            try sealer.open(sealed, recordID: "request-2")
        }
    }

    @Test func wrongKeyIsRefused() throws {
        let sealed = try sealer.seal(Data("ciao".utf8), recordID: "request-1")
        #expect(throws: RecordSealer.Failure.unreadable) {
            try RecordSealer(key: SymmetricKey(size: .bits256)).open(sealed, recordID: "request-1")
        }
    }

    @Test func alteredBytesAreRefused() throws {
        var sealed = try sealer.seal(Data("ciao".utf8), recordID: "request-1")
        sealed[sealed.count - 1] ^= 1
        #expect(throws: RecordSealer.Failure.unreadable) {
            try sealer.open(sealed, recordID: "request-1")
        }
    }

    @Test func everySealUsesAFreshNonce() throws {
        let first = try sealer.seal(Data("ciao".utf8), recordID: "r")
        let second = try sealer.seal(Data("ciao".utf8), recordID: "r")
        #expect(first != second)
    }
}
