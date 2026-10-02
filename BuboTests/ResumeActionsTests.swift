import Foundation
import Testing
@testable import Bubo

struct ResumeActionsTests {
    let project = URL(filePath: "/tmp/progetto")

    func result(of source: ConversationSource, id: String) -> ConversationResult {
        ConversationResult(id: id, title: "Correggi il login", source: source, project: project, conversation: "t-2",
                           date: .now)
    }

    func session(in phase: Session.Phase) -> Session {
        var session = Session(id: UUID(), title: "Prova", project: project, activity: .ferma)
        session.phase = phase
        return session
    }

    @Test func theCLIHistoryAlwaysResumesInANewSessionThatForksItAll() {
        let resumption = ResumeActions.resumption(of: result(of: .cli, id: "c-1"), among: [])
        guard case let .startSession(draft) = resumption else {
            Issue.record("Expected a new Sessione, got \(String(describing: resumption))")
            return
        }
        #expect(draft.conversation?.id == "t-2")
        #expect(draft.conversation?.folder == project)
        #expect(draft.upToMessage == nil)
    }

    @Test func anOpenSessioneOfBuboResumesItself() {
        let open = session(in: .aperta)
        #expect(ResumeActions.resumption(of: result(of: .session, id: open.id.uuidString), among: [open])
            == .bringToFront(open.id))
    }

    @Test func anArchiviataSessioneOfBuboOpensAgain() {
        let archived = session(in: .archiviata)
        #expect(ResumeActions.resumption(of: result(of: .session, id: archived.id.uuidString), among: [archived])
            == .reopen(archived.id))
    }

    @Test func aFusaSessioneOrOneGoneCannotBeResumed() {
        let merged = session(in: .fusa)
        #expect(ResumeActions.resumption(of: result(of: .session, id: merged.id.uuidString), among: [merged]) == nil)
        #expect(ResumeActions.resumption(of: result(of: .session, id: UUID().uuidString), among: [merged]) == nil)
    }

    @Test func continuaDaQuiForksTheConversationUpToTheMessage() {
        let draft = ResumeActions.draft(continuing: result(of: .session, id: UUID().uuidString), upTo: "m-3")
        #expect(draft.conversation?.id == "t-2")
        #expect(draft.conversation?.folder == project)
        #expect(draft.upToMessage == "m-3")
        #expect(draft.canStartEmpty)
    }
}
