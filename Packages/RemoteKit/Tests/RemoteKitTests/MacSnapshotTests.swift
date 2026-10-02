import CryptoKit
import Foundation
import RemoteKit
import Testing

struct MacSnapshotTests {
    let channel = InMemoryRemoteChannel()
    let macID = UUID()
    let deviceID = UUID()
    let sealer = RecordSealer(key: SymmetricKey(size: .bits256))

    func save(_ value: some Encodable, kind: RemoteRecord.Kind, named name: String, expiresAt: Date = .now.addingTimeInterval(86_400),
              sealer: RecordSealer? = nil) async throws {
        let sealer = sealer ?? self.sealer
        let id = sealer.recordID(named: name)
        try await channel.save(RemoteRecord(id: id, kind: kind, macID: macID, deviceID: deviceID, expiresAt: expiresAt,
                                            payload: try sealer.seal(value, recordID: id)))
    }

    @Test func snapshotOpensTheHeartbeatAndTheCards() async throws {
        let heartbeat = Heartbeat(macName: "Mac Studio", sentAt: Date(timeIntervalSince1970: 1_000))
        let card = SessionCard(id: UUID(), title: "Correggi il login", project: "bubo", activity: .lavora, phase: .aperta,
                               excerpt: "Ho corretto il redirect.", diff: .init(files: 3, addedLines: 40, removedLines: 2))
        try await save(heartbeat, kind: .heartbeat, named: "heartbeat")
        try await save(card, kind: .sessionCard, named: "sessionCard/\(card.id)")

        let snapshot = try await channel.snapshot(macID: macID, deviceID: deviceID, sealer: sealer)

        #expect(snapshot == MacSnapshot(heartbeat: heartbeat, cards: [card]))
    }

    @Test func recordsSealedWithAnotherKeyAreLeftOut() async throws {
        let other = RecordSealer(key: SymmetricKey(size: .bits256))
        try await save(SessionCard(id: UUID(), title: "Altro", project: "x", activity: .ferma, phase: .aperta),
                       kind: .sessionCard, named: "sessionCard/altro", sealer: other)

        #expect(try await channel.snapshot(macID: macID, deviceID: deviceID, sealer: sealer).cards.isEmpty)
    }

    @Test func recordIDIsStableAndDependsOnTheKey() {
        let other = RecordSealer(key: SymmetricKey(size: .bits256))
        #expect(sealer.recordID(named: "heartbeat") == sealer.recordID(named: "heartbeat"))
        #expect(sealer.recordID(named: "heartbeat") != other.recordID(named: "heartbeat"))
        #expect(sealer.recordID(named: "heartbeat").count == 32)
    }

    @Test func expiredRecordsAreDeleted() async throws {
        try await save(Heartbeat(macName: "Mac", sentAt: .now), kind: .heartbeat, named: "old",
                       expiresAt: .now.addingTimeInterval(-1))
        try await save(Heartbeat(macName: "Mac", sentAt: .now), kind: .heartbeat, named: "new")

        try await channel.deleteRecords(of: macID, expiringBefore: .now)

        #expect(try await channel.records(macID: macID, deviceID: deviceID).map(\.id) == [sealer.recordID(named: "new")])
    }

    @Test(arguments: [(0.0, false, false), (121, false, true), (10, true, true)])
    func heartbeatIsStaleAfterTwoMinutesOrAsleep(age: TimeInterval, isAsleep: Bool, isStale: Bool) {
        let now = Date.now
        let heartbeat = Heartbeat(macName: "Mac", sentAt: now.addingTimeInterval(-age), isAsleep: isAsleep)
        #expect(heartbeat.isStale(at: now) == isStale)
    }
}

struct SessionCardTests {
    @Test func cardsAreGroupedByProjectWithWaitingFirst() {
        func card(_ title: String, _ project: String, _ activity: SessionCard.Activity) -> SessionCard {
            SessionCard(id: UUID(), title: title, project: project, activity: activity, phase: .aperta)
        }
        let groups = SessionCard.groupedByProject([
            card("Login", "web", .lavora), card("Branch", "web", .attende),
            card("Docs", "api", .ferma), card("Build", "web", .errore),
        ])
        #expect(groups.map(\.project) == ["api", "web"])
        #expect(groups.last?.cards.map(\.title) == ["Branch", "Build", "Login"])
    }
}
