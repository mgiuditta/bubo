import Foundation
import Testing
@testable import Bubo

@MainActor
struct MenuBarContentTests {
    private func session(_ title: String, _ activity: Session.Activity, waitingFor minutes: Double = 0) -> Session {
        Session(id: UUID(), title: title, project: URL(filePath: "/tmp"), activity: activity,
                activitySince: .now.addingTimeInterval(-minutes * 60))
    }

    @Test func listsAttendeTeLongestWaitFirstThenErrore() {
        let recent = session("Recente", .attende, waitingFor: 1)
        let oldest = session("Vecchia", .attende, waitingFor: 30)
        let failed = session("Rotta", .errore)
        let sessions = [failed, session("Lavora", .lavora), recent, session("Ferma", .ferma), oldest]

        #expect(MenuBarContent.waitingSessions(in: sessions).map(\.title) == ["Vecchia", "Recente", "Rotta"])
    }

    @Test func leavesOutTheSessioniNoLongerOpen() {
        var archived = session("Archiviata", .attende)
        archived.phase = .archiviata

        #expect(MenuBarContent.waitingSessions(in: [archived]).isEmpty)
    }
}
