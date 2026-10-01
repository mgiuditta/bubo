import Foundation
import Testing
@testable import Bubo

/// The notifications and the Dock badge of the Sessioni in Attende te, with no real notification ever asked for.
@MainActor
struct WaitingAlertsTests {
    /// What the alerts did, in order.
    final class Log {
        var badges: [Int] = []
        var announced: [String] = []
        /// The Richiesta of each announcement, `nil` for none.
        var requests: [PermissionRequest.ID?] = []
        var withdrawn: [UUID] = []
        var bounces = 0
    }

    let log = Log()

    func makeAlerts(isSeen: Bool = false, isAllowed: Bool = true) -> WaitingAlerts {
        WaitingAlerts(isSeen: { isSeen }, announce: { [log] session, pending in
            log.announced.append(session.title)
            log.requests.append(pending?.id)
            return isAllowed
        }, withdraw: { [log] in log.withdrawn.append($0) }, badge: { [log] in log.badges.append($0) },
        bounce: { [log] in log.bounces += 1 })
    }

    static func session(_ title: String, _ activity: Session.Activity) -> Session {
        Session(id: UUID(), title: title, project: URL(filePath: "/tmp"), activity: activity)
    }

    @Test func eachSessioneThatStartsWaitingIsAnnouncedOnceAndCounted() async {
        let alerts = makeAlerts()
        var first = Self.session("a", .lavora)
        let second = Self.session("b", .attende)

        alerts.follow([first, second])
        first.summary = "Ho letto il file."
        alerts.follow([first, second])
        first.enter(.attende)
        alerts.follow([first, second])
        alerts.follow([first, second])
        await alerts.announcing?.value

        #expect(log.badges == [1, 2])
        #expect(log.announced.sorted() == ["a", "b"])
        #expect(log.bounces == 0)
    }

    @Test func aSessioneThatStopsWaitingLosesItsNotification() {
        let alerts = makeAlerts()
        var session = Self.session("a", .attende)

        alerts.follow([session])
        session.enter(.lavora)
        alerts.follow([session])

        #expect(log.badges == [1, 0])
        #expect(log.withdrawn == [session.id])
    }

    @Test func aSessioneThatWaitsAgainIsAnnouncedAgain() async {
        let alerts = makeAlerts()
        var session = Self.session("a", .attende)

        alerts.follow([session])
        await alerts.announcing?.value
        session.enter(.lavora)
        alerts.follow([session])
        session.enter(.attende)
        alerts.follow([session])
        await alerts.announcing?.value

        #expect(log.announced == ["a", "a"])
    }

    @Test func withTheHUDInFrontOnlyTheBadgeMoves() {
        let alerts = makeAlerts(isSeen: true)

        alerts.follow([Self.session("a", .attende)])

        #expect(log.badges == [1])
        #expect(log.announced.isEmpty)
        #expect(alerts.announcing == nil)
    }

    @Test func withNotificationsDeniedTheDockIconBounces() async {
        let alerts = makeAlerts(isAllowed: false)

        alerts.follow([Self.session("a", .attende)])
        await alerts.announcing?.value

        #expect(log.badges == [1])
        #expect(log.bounces == 1)
    }

    @Test func anArchivedSessioneIsNotCounted() {
        let alerts = makeAlerts()
        var archived = Self.session("a", .attende)
        archived.phase = .archiviata

        alerts.follow([archived, Self.session("b", .ferma)])

        #expect(log.badges.isEmpty)
        #expect(log.announced.isEmpty)
    }

    @Test func theNotificationFollowsTheOldestRichiestaAndNeverOutlivesIt() async {
        let alerts = makeAlerts()
        let session = Self.session("a", .attende)
        var requests = RequestCenter()
        _ = requests.receive(PermissionRequest(id: "1", tool: "Bash", command: "ls"), in: session.id,
                             risk: Risk(level: .lettura))
        _ = requests.receive(PermissionRequest(id: "2", tool: "Bash", command: "npm test"), in: session.id,
                             risk: Risk(level: .modifica))

        alerts.follow([session], requests: requests)
        await alerts.announcing?.value
        _ = requests.answer("1", in: session.id, with: .allowOnce)
        alerts.follow([session], requests: requests)
        await alerts.announcing?.value
        _ = requests.answer("2", in: session.id, with: .deny)
        alerts.follow([session], requests: requests)
        await alerts.announcing?.value

        #expect(log.requests == ["1", "2"])
        // Withdrawn before Richiesta 2 is posted, and when no Richiesta is left.
        #expect(log.withdrawn == [session.id, session.id])
        #expect(log.badges == [1])
    }

    @Test func aRichiestaThatArrivesAfterTheWaitIsAnnouncedWithIt() async {
        let alerts = makeAlerts()
        let session = Self.session("a", .attende)
        var requests = RequestCenter()

        alerts.follow([session], requests: requests)
        await alerts.announcing?.value
        _ = requests.receive(PermissionRequest(id: "1", tool: "Bash", command: "ls"), in: session.id,
                             risk: Risk(level: .lettura))
        alerts.follow([session], requests: requests)
        await alerts.announcing?.value

        #expect(log.requests == [nil, "1"])
    }
}
