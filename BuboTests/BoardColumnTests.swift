import Foundation
import Testing
@testable import Bubo

/// The rule of the Board's columns, and the Colonna grouping the same way.
struct BoardColumnTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let hour: TimeInterval = 60 * 60

    private static func session(_ title: String, _ activity: Session.Activity, since: TimeInterval = 0,
                                phase: Session.Phase = .aperta, mergedAt: Date? = nil) -> Session {
        var session = Session(id: UUID(), title: title, project: URL(filePath: "/tmp"), activity: activity,
                              activitySince: Date(timeIntervalSince1970: since))
        session.phase = phase
        session.mergedAt = mergedAt
        return session
    }

    /// Every Aperta Sessione, by Attività and PR: the PR counts only when open and the Sessione is Ferma.
    @Test(arguments: [
        (Session.Activity.attende, nil, BoardColumn.attendeTe), (.attende, .open, .attendeTe),
        (.attende, .closed, .attendeTe), (.attende, .merged, .attendeTe),
        (.errore, nil, .attendeTe), (.errore, .open, .attendeTe), (.errore, .closed, .attendeTe),
        (.errore, .merged, .attendeTe),
        (.lavora, nil, .lavora), (.lavora, .open, .lavora), (.lavora, .closed, .lavora), (.lavora, .merged, .lavora),
        (.ferma, nil, .daGuardare), (.ferma, .open, .prAperta), (.ferma, .closed, .daGuardare),
        (.ferma, .merged, .daGuardare),
    ] as [(Session.Activity, BoardColumn.PullRequest?, BoardColumn)])
    func anApertaSessioneGoesByItsAttivitaThenItsPR(activity: Session.Activity, pullRequest: BoardColumn.PullRequest?,
                                                    column: BoardColumn) {
        #expect(BoardColumn(phase: .aperta, activity: activity, pullRequest: pullRequest, mergedAt: nil,
                            now: Self.now) == column)
    }

    /// Fusa and Archiviata ignore the Attività and the PR: only the merge and its 24 h count.
    @Test(arguments: Session.Activity.allCases)
    func aMergedSessioneIsInFusaFor24Hours(activity: Session.Activity) {
        for pullRequest in [nil, .open, .closed, .merged] as [BoardColumn.PullRequest?] {
            func column(_ phase: Session.Phase, mergedHoursAgo hours: Double?) -> BoardColumn? {
                BoardColumn(phase: phase, activity: activity, pullRequest: pullRequest,
                            mergedAt: hours.map { Self.now.addingTimeInterval(-$0 * Self.hour) }, now: Self.now)
            }
            #expect(column(.fusa, mergedHoursAgo: nil) == .fusa)
            #expect(column(.fusa, mergedHoursAgo: 0) == .fusa)
            #expect(column(.archiviata, mergedHoursAgo: 23) == .fusa)
            #expect(column(.fusa, mergedHoursAgo: 25) == nil)
            #expect(column(.archiviata, mergedHoursAgo: 25) == nil)
            #expect(column(.archiviata, mergedHoursAgo: nil) == nil)
        }
    }

    @Test func errorWithAMergedPRWaitsForTheUser() {
        #expect(BoardColumn(phase: .aperta, activity: .errore, pullRequest: .merged, mergedAt: nil, now: Self.now)
            == .attendeTe)
    }

    @Test func aStoppedSessioneOnTheCheckoutIsToLookAt() {
        var session = Self.session("README", .ferma)
        session.isOnCheckout = true

        #expect(BoardColumn(session, at: Self.now) == .daGuardare)
    }

    @Test func everyColumnIsThereInOrderAndAttendeTeHasTheLongestWaitOnTop() {
        let columns = BoardColumn.columns(of: [Self.session("a", .ferma, since: 5), Self.session("b", .attende, since: 20),
                                               Self.session("c", .ferma, since: 9), Self.session("d", .errore, since: 10)],
                                          at: Self.now)

        #expect(columns.map(\.column) == [.attendeTe, .lavora, .daGuardare, .prAperta, .fusa])
        #expect(columns.map { $0.sessions.map(\.title) } == [["d", "b"], [], ["c", "a"], [], []])
    }

    /// The recorded sequences of the Attività's machine, one Sessione each: after every event the Board's column
    /// and the Colonna's group are the same.
    @Test func theBoardAndTheColonnaAgreeOnEveryEvent() throws {
        let sequences = [
            [ActivityTests.running, #"{"v":3,"type":"summary","id":"a1","text":"Context Usage"}"#, ActivityTests.idle],
            [ActivityTests.running, ActivityTests.waiting, ActivityTests.running, ActivityTests.idle],
            [ActivityTests.running, ActivityTests.waiting],
        ]
        var failed = Self.session("Errore", .errore)
        failed.failure = "fatal"
        let merged = Self.session("Fusa", .ferma, phase: .archiviata, mergedAt: Self.now.addingTimeInterval(-Self.hour))
        let archived = Self.session("Archiviata", .ferma, phase: .archiviata)
        let replays = try sequences.map { try ActivityTests.replay($0) }
            + [failed, merged, archived].map { try ActivityTests.replay([ActivityTests.idle], from: $0) }

        for step in 0..<4 {
            let sessions = replays.map { $0[min(step, $0.count - 1)] }
            let groups = SessionColumn.groups(of: sessions, at: Self.now)
            for session in sessions {
                let group = groups.first { $0.sessions.contains { $0.id == session.id } }
                #expect(group?.column == BoardColumn(session, at: Self.now))
            }
        }
    }

    /// Bubo quits and starts again: the Sessioni not in a turn come back in the same column.
    @MainActor
    @Test func afterARestartEveryCardIsInTheSameColumn() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date.now
        let sessions = [Self.session("ferma", .ferma), Self.session("errore", .errore),
                        Self.session("fusa", .ferma, phase: .fusa, mergedAt: now.addingTimeInterval(-60)),
                        Self.session("fusa ieri", .ferma, phase: .archiviata, mergedAt: now.addingTimeInterval(-Self.hour)),
                        Self.session("archiviata", .ferma, phase: .archiviata)]
        try JSONEncoder().encode(sessions).write(to: file)

        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }

        #expect(store.sessions.map { BoardColumn($0, at: now) } == sessions.map { BoardColumn($0, at: now) })
    }

    @Test func fiveHundredSessioniTakeLessThan5Milliseconds() {
        let activities = Session.Activity.allCases
        let sessions = (0..<500).map { index in
            Self.session("\(index)", activities[index % activities.count], since: Double(index),
                         phase: index % 7 == 0 ? .archiviata : .aperta,
                         mergedAt: index % 14 == 0 ? Self.now.addingTimeInterval(-Self.hour) : nil)
        }

        let elapsed = ContinuousClock().measure { _ = BoardColumn.columns(of: sessions, at: Self.now) }

        #expect(elapsed < .milliseconds(5))
    }

    /// Fondi… and Archivia only once the agent has finished: never on a Sessione waiting for the user or in Errore.
    @Test func onlyDaGuardareAndPRApertaHaveTheNextStep() {
        #expect(BoardColumn.allCases.filter(\.hasNextStep) == [.daGuardare, .prAperta])
    }
}
