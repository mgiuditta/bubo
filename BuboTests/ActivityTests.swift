import Foundation
import Testing
@testable import Bubo

/// The machine of the Attività, fed with what the bridge writes for recorded sequences of the SDK.
struct ActivityTests {
    /// Applies the bridge's `lines` to a new Sessione one second apart, returning the Sessione after each line.
    static func replay(_ lines: [String], from session: Session = Session(id: UUID(), title: "Prova",
                                                                           project: URL(filePath: "/tmp"))) throws
        -> [Session] {
        var session = session
        return try lines.enumerated().map { second, line in
            guard case let .progress(_, progress) = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            else { throw CancellationError() }
            session.apply(progress, at: Date(timeIntervalSince1970: Double(second)))
            return session
        }
    }

    static let running = #"{"v":4,"type":"state","id":"a1","state":"running"}"#
    static let waiting = #"{"v":4,"type":"state","id":"a1","state":"requires_action"}"#
    static let idle = #"{"v":4,"type":"state","id":"a1","state":"idle"}"#

    /// `/context` with Claude Code 2.1.286, as `bridge/src/activity.test.ts` records it.
    @Test func aRecordedTurnWorksThenStops() throws {
        let sessions = try Self.replay([Self.running, #"{"v":4,"type":"summary","id":"a1","text":"Context Usage"}"#,
                                        Self.idle])

        #expect(sessions.map(\.activity) == [.lavora, .lavora, .ferma])
        #expect(sessions.last?.summary == "Context Usage")
        #expect(sessions.last?.activitySince == Date(timeIntervalSince1970: 2))
    }

    /// From the SDK's types: `canUseTool` pending is `requires_action`, its answer `running` again.
    @Test func aPendingPermissionIsAttendeTeUntilTheTurnGoesOn() throws {
        let sessions = try Self.replay([Self.running, Self.waiting, Self.running])

        #expect(sessions.map(\.activity) == [.lavora, .attende, .lavora])
        #expect(sessions[1].activitySince == Date(timeIntervalSince1970: 1))
    }

    /// The result comes before the subagents in the background end; only `idle`, after them, stops the Sessione.
    @Test func aSessioneWithSubagentsStillWorkingIsNeverFerma() throws {
        let sessions = try Self.replay([Self.running, #"{"v":4,"type":"summary","id":"a1","text":"Ho lanciato 2 agenti."}"#,
                                        Self.running])

        #expect(sessions.allSatisfy { $0.activity == .lavora })
        #expect(sessions.last?.activitySince == Date(timeIntervalSince1970: 0))
    }

    /// Recorded with an invalid key: `idle` arrives after the failed result, and must not hide the Errore.
    @Test func idleAfterAFailureKeepsErrore() throws {
        var failed = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"))
        failed.enter(.errore, at: Date(timeIntervalSince1970: 0))

        #expect(try Self.replay([Self.idle], from: failed).map(\.activity) == [.errore])
    }

    @MainActor
    @Test func aSessioneWaitingWhenBuboQuitIsStopped() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode([Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .attende)])
            .write(to: file)

        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }

        #expect(store.sessions.map(\.activity) == [.ferma])
        #expect(store.sessions.map(\.isInterrupted) == [true])
    }

    @Test func attendeTeComesFirstWithTheLongestWaitOnTop() {
        func session(_ title: String, _ activity: Session.Activity, since: TimeInterval) -> Session {
            Session(id: UUID(), title: title, project: URL(filePath: "/tmp"), activity: activity,
                    activitySince: Date(timeIntervalSince1970: since))
        }
        let groups = Session.grouped([session("a", .ferma, since: 0), session("b", .attende, since: 20),
                                      session("c", .lavora, since: 5), session("d", .attende, since: 10),
                                      session("e", .errore, since: 1)])

        #expect(groups.map(\.activity) == [.attende, .errore, .lavora, .ferma])
        #expect(groups.first?.sessions.map(\.title) == ["d", "b"])
    }

    @Test func orbitaAndStrisciaListTheSessioniInTheColonnasOrder() {
        func session(_ title: String, _ activity: Session.Activity, since: TimeInterval) -> Session {
            Session(id: UUID(), title: title, project: URL(filePath: "/tmp"), activity: activity,
                    activitySince: Date(timeIntervalSince1970: since))
        }
        let sessions = Session.inActivityOrder([session("a", .ferma, since: 0), session("b", .attende, since: 20),
                                                session("c", .lavora, since: 5), session("d", .attende, since: 10)])

        #expect(sessions.map(\.title) == ["d", "b", "c", "a"])
    }

    @Test(arguments: [
        ([Session.Activity](), OrbState.idle),
        ([.ferma, .errore], .idle),
        ([.ferma, .lavora], .working),
        ([.lavora, .attende, .errore], .listening),
    ])
    func theOrbFollowsTheOpenSessioni(activities: [Session.Activity], state: OrbState) {
        let sessions = activities.map { Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: $0) }
        #expect(OrbState(following: sessions) == state)
    }

    @Test func withAFocusTheOrbFollowsThatSessioneAlone() {
        let waiting = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .attende)
        let working = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .lavora)
        #expect(OrbState(following: [waiting, working], focus: working.id) == .working)
        #expect(OrbState(following: [waiting, working], focus: UUID()) == .listening)
    }

    @Test func anArchivedSessioneDoesNotMoveTheOrb() {
        var archived = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .attende)
        archived.phase = .archiviata
        #expect(OrbState(following: [archived]) == .idle)
    }
}
