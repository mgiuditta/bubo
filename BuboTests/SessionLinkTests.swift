import Foundation
import Testing
@testable import Bubo

/// `bubo://sessione/<id>`: the link of the Riassunto di Sessione notes, checked as input anyone can write; it shows a
/// Sessione and never starts one.
@MainActor
struct SessionLinkTests {
    let id = UUID()

    private func session(_ phase: Session.Phase, conversations: [String] = ["c1", "c2"]) -> Session {
        var session = Session(id: id, title: "Esporta in CSV", project: URL(filePath: "/tmp/progetto"))
        session.phase = phase
        session.conversations = conversations
        return session
    }

    @Test func readsTheLinkOfTheSummaryNote() throws {
        let link = try #require(SessionLink(URL(string: "bubo://sessione/\(id.uuidString.lowercased())")!))

        #expect(link.id == id)
    }

    @Test(arguments: [
        "bubo://sessione/",
        "bubo://sessione/non-un-id",
        "bubo://sessione/\(UUID().uuidString)/altro",
        "bubo://sessione/\(UUID().uuidString)?avvia=1",
        "bubo://sessione/\(UUID().uuidString)#x",
        "bubo://draft/\(UUID().uuidString)",
        "https://sessione/\(UUID().uuidString)",
    ])
    func refusesAnythingElse(_ text: String) {
        #expect(SessionLink(URL(string: text)!) == nil)
    }

    @Test(arguments: [Session.Phase.aperta, .inRevisione])
    func aLiveSessioneOpensInTheHUD(_ phase: Session.Phase) throws {
        let link = try #require(SessionLink(URL(string: "bubo://sessione/\(id.uuidString)")!))

        #expect(link.destination(among: [session(phase)]) == .hud(id))
    }

    @Test(arguments: [Session.Phase.fusa, .archiviata])
    func aClosedSessioneOpensItsLatestConversationInTheCronologia(_ phase: Session.Phase) throws {
        let link = try #require(SessionLink(URL(string: "bubo://sessione/\(id.uuidString)")!))

        guard case .history(let result) = link.destination(among: [session(phase)]) else {
            Issue.record("Not the Cronologia")
            return
        }
        #expect(result.id == id.uuidString)
        #expect(result.source == .session)
        #expect(result.conversation == "c2")
    }

    @Test func anUnknownIdIsNoLongerAvailable() throws {
        let link = try #require(SessionLink(URL(string: "bubo://sessione/\(UUID().uuidString)")!))

        #expect(link.destination(among: [session(.aperta)]) == .unavailable)
    }

    @Test func aClosedSessioneWithNoConversationIsNoLongerAvailable() throws {
        let link = try #require(SessionLink(URL(string: "bubo://sessione/\(id.uuidString)")!))

        #expect(link.destination(among: [session(.archiviata, conversations: [])]) == .unavailable)
    }
}
