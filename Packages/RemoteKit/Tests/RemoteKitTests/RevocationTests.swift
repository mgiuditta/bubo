import CryptoKit
import Foundation
import RemoteKit
import Testing

struct RevocationTests {
    @Test func responsesSentBeforeListeningArrive() async throws {
        let fixture = try PairingFixture()
        let channel = InMemoryRemoteChannel()
        try await channel.send(fixture.response)
        var responses = await channel.responses(to: fixture.invitation.id).makeAsyncIterator()
        #expect(await responses.next() == fixture.response)
    }

    /// After a revocation, either side finds 0 records of the pair; other pairs keep theirs.
    @Test func revocationDeletesThePairsRecords() async throws {
        let fixture = try PairingFixture()
        let channel = InMemoryRemoteChannel()
        let macID = fixture.invitation.macID
        let sealer = RecordSealer(key: try fixture.macSecrets().key)
        let otherDevice = UUID()
        for (index, deviceID) in [fixture.deviceID, fixture.deviceID, otherDevice].enumerated() {
            let id = "card-\(index)"
            try await channel.save(RemoteRecord(
                id: id, kind: .sessionCard, macID: macID, deviceID: deviceID,
                expiresAt: .now.addingTimeInterval(86_400),
                payload: try sealer.seal(Data("Sessione".utf8), recordID: id)
            ))
        }
        var revocations = await channel.revocations().makeAsyncIterator()

        try await channel.revoke(Revocation(macID: macID, deviceID: fixture.deviceID))

        #expect(await revocations.next() == Revocation(macID: macID, deviceID: fixture.deviceID))
        #expect(try await channel.records(macID: macID, deviceID: fixture.deviceID).isEmpty)
        #expect(try await channel.records(macID: macID, deviceID: otherDevice).count == 1)
    }
}
