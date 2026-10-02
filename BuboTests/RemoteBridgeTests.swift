import CryptoKit
import Foundation
import RemoteKit
import Testing
@testable import Bubo

/// The Telecomando's switch, which the tests turn off.
private final class RemoteSwitch {
    var isOn = true
}

@MainActor
struct RemoteBridgeTests {
    let channel = InMemoryRemoteChannel()
    let macID = UUID()
    let phone = PairedDevice(id: UUID(), name: "iPhone di prova", signingKey: Data(),
                             recordKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, pairedAt: .now)
    let macOnly = MacOnlyProjects(defaults: UserDefaults(suiteName: "RemoteBridgeTests-\(UUID().uuidString)")!)
    private let remoteSwitch = RemoteSwitch()
    let bridge: RemoteBridge
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let app = URL(filePath: "/Users/u/Sviluppo/gestionale")
    let secret = URL(filePath: "/Users/u/Sviluppo/segreto")

    init() {
        let phone = phone
        let remoteSwitch = remoteSwitch
        bridge = RemoteBridge(macID: macID, macName: "Mac Studio", channel: channel, devices: { [phone] },
                              isOn: { remoteSwitch.isOn }, macOnly: macOnly) { _ in
            SessionCard.DiffStats(files: 3, addedLines: 40, removedLines: 2)
        }
    }

    /// What the paired iPhone reads.
    func phoneSnapshot() async throws -> MacSnapshot {
        try await channel.snapshot(macID: macID, deviceID: phone.id, sealer: RecordSealer(key: SymmetricKey(data: phone.recordKey)))
    }

    func cardCount() async throws -> Int {
        try await channel.records(macID: macID, deviceID: phone.id).count { $0.kind == .sessionCard }
    }

    func session(_ title: String, in project: URL, activity: Session.Activity = .lavora) -> Session {
        Session(id: UUID(), title: title, project: project, activity: activity, summary: "Leggo i test.")
    }

    @Test func cardCarriesTitleProjectActivityPhaseExcerptAndDiff() async throws {
        let login = session("Correggi il login", in: app)

        await bridge.publish([login], now: now)

        #expect(try await phoneSnapshot().cards == [SessionCard(
            id: login.id, title: "Correggi il login", project: "gestionale", activity: .lavora, phase: .aperta,
            excerpt: "Leggo i test.", diff: .init(files: 3, addedLines: 40, removedLines: 2)
        )])
    }

    @Test func macOnlyProjectWritesNoCards() async throws {
        macOnly.setMacOnly(true, for: secret)

        await bridge.publish([session("Ruota le chiavi", in: secret), session("Correggi il login", in: app)], now: now)

        #expect(try await phoneSnapshot().cards.map(\.project) == ["gestionale"])
    }

    @Test func projectTurnedMacOnlyLosesItsCards() async throws {
        let sessions = [session("Ruota le chiavi", in: secret), session("Pulisci i log", in: secret)]
        await bridge.publish(sessions, now: now)
        #expect(try await cardCount() == 2)

        macOnly.setMacOnly(true, for: secret)
        await bridge.publish(sessions, now: now.addingTimeInterval(1))

        #expect(try await cardCount() == 0)
    }

    @Test func activityChangeReachesThePhone() async throws {
        var login = session("Correggi il login", in: app)
        await bridge.publish([login], now: now)

        login.enter(.attende, at: now.addingTimeInterval(6))
        await bridge.publish([login], now: now.addingTimeInterval(6))

        #expect(try await phoneSnapshot().cards.map(\.activity) == [.attende])
    }

    @Test func cardIsWrittenAtMostOnceEveryFiveSeconds() async throws {
        var login = session("Correggi il login", in: app)
        await bridge.publish([login], now: now)

        login.enter(.attende)
        let due = await bridge.publish([login], now: now.addingTimeInterval(2))
        #expect(due == now.addingTimeInterval(RemoteBridge.cardInterval))
        #expect(try await phoneSnapshot().cards.map(\.activity) == [.lavora])

        #expect(await bridge.publish([login], now: now.addingTimeInterval(5)) == nil)
        #expect(try await phoneSnapshot().cards.map(\.activity) == [.attende])
    }

    @Test func archivedSessionLosesItsCard() async throws {
        var login = session("Correggi il login", in: app)
        await bridge.publish([login], now: now)

        login.phase = .archiviata
        await bridge.publish([login], now: now.addingTimeInterval(1))

        #expect(try await cardCount() == 0)
    }

    @Test func nothingLeavesWithTheTelecomandoOff() async throws {
        remoteSwitch.isOn = false

        await bridge.publish([session("Correggi il login", in: app)], now: now)
        await bridge.beat(now: now)

        #expect(try await channel.records(macID: macID, deviceID: phone.id).isEmpty)
    }

    @Test func turningOffWithdrawsTheCardsAndTheHeartbeat() async throws {
        let login = session("Correggi il login", in: app)
        await bridge.publish([login], now: now)
        await bridge.beat(now: now)

        remoteSwitch.isOn = false
        await bridge.publish([login], now: now.addingTimeInterval(1))

        #expect(try await channel.records(macID: macID, deviceID: phone.id).isEmpty)
    }

    @Test func heartbeatTellsTheMacAndWhetherItSleeps() async throws {
        await bridge.beat(now: now)
        #expect(try await phoneSnapshot().heartbeat == Heartbeat(macName: "Mac Studio", sentAt: now))

        await bridge.beat(isAsleep: true, now: now.addingTimeInterval(30))
        #expect(try await phoneSnapshot().heartbeat?.isStale(at: now.addingTimeInterval(31)) == true)
        #expect(try await channel.records(macID: macID, deviceID: phone.id).count == 1)
    }

    @Test func cleanupLeavesNoRecordOlderThanADay() async throws {
        await bridge.publish([session("Correggi il login", in: app)], now: now)
        await bridge.beat(now: now)
        await bridge.beat(now: now.addingTimeInterval(RemoteBridge.recordLifetime))

        await bridge.cleanUp(now: now.addingTimeInterval(RemoteBridge.recordLifetime + 1))

        let records = try await channel.records(macID: macID, deviceID: phone.id)
        #expect(records.map(\.kind) == [.heartbeat])
    }

    @Test func recordsShowNoTitleNorProjectInTheClear() async throws {
        let login = session("Correggi il login", in: app)
        await bridge.publish([login], now: now)

        let record = try #require(try await channel.records(macID: macID, deviceID: phone.id).first)
        #expect(!record.id.contains(login.id.uuidString))
        #expect(record.payload.range(of: Data("Correggi".utf8)) == nil)
        #expect(record.payload.range(of: Data("gestionale".utf8)) == nil)
    }
}
