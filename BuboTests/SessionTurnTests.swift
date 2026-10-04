import Foundation
import Testing
@testable import Bubo

/// When a Sessione takes a new turn from the window's composer.
struct SessionTurnTests {
    private func session(activity: Session.Activity, phase: Session.Phase = .aperta) -> Session {
        var session = Session(id: UUID(), title: "Login", project: URL(filePath: "/tmp/bubo", directoryHint: .isDirectory),
                              activity: activity)
        session.phase = phase
        return session
    }

    @Test(arguments: [Session.Activity.ferma, .errore])
    func anOpenSessionAtRestTakesATurn(activity: Session.Activity) {
        #expect(session(activity: activity).canTakeTurn)
    }

    @Test(arguments: [Session.Activity.lavora, .attende])
    func aWorkingOrWaitingSessionDoesNot(activity: Session.Activity) {
        #expect(!session(activity: activity).canTakeTurn)
    }

    @Test func anArchivedSessionDoesNot() {
        #expect(!session(activity: .ferma, phase: .archiviata).canTakeTurn)
    }
}
