import Foundation
import Testing
@testable import Bubo

/// "Trasforma in Sessione" (#679): the Sessione starts at once, the sheet only when it cannot.
struct TurnIntoSessionTests {
    let draft = SessionDraft(turns: [QuestionTurn(prompt: "Aggiungi la call", answer: "Fatto")])

    @Test func aDomandaStartsItsSessioneWithoutTheSheet() {
        let hud = HUDPresenter()
        let id = UUID()
        hud.startSession = { _ in id }

        hud.turnIntoSession(draft)

        #expect(hud.revealedSession == id)
        #expect(!hud.isCreatingSession)
    }

    @Test func withoutATrustedProgettoTheSheetOpens() {
        let hud = HUDPresenter()
        hud.startSession = { _ in nil }

        hud.turnIntoSession(draft)

        #expect(hud.isCreatingSession)
        #expect(hud.revealedSession == nil)
    }
}
