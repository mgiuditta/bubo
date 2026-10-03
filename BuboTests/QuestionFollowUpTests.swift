import Foundation
import Testing
@testable import Bubo

/// The seguiti of a Domanda in the Bolla (#637): context kept, ⌘N and 15 minutes start over, all turns to a Sessione.
@Suite(.timeLimit(.minutes(1)))
struct QuestionFollowUpTests {
    /// A clock the test moves by hand.
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
    }

    /// A bridge played by `/bin/sh` that says whether the prompt it got carries the first turn, followed by more text.
    static let bridge = #"""
        while read -r line; do
          id=$(printf "%s" "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'Chi era Volta?\n'*) text="con contesto" ;;
            *) text="senza contesto" ;;
          esac
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$text\"}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    let clock = Clock()
    let model: QuestionModel

    init() {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let clock = clock
        model = QuestionModel(cli: cli, orb: OrbControls(), bridgeExecutable: URL(filePath: "/bin/sh"),
                              bridgeArguments: ["-c", Self.bridge],
                              defaults: UserDefaults(suiteName: UUID().uuidString)!, onDevice: .off,
                              now: { clock.now })
    }

    func ask(_ text: String) async {
        model.prompt = text
        model.ask()
        await model.answering?.value
    }

    @Test func aSeguitoKeepsTheContextOfTheFirstPrompt() async {
        await ask("Chi era Volta?")
        #expect(model.answer == "senza contesto")

        await ask("E dove è nato?")

        #expect(model.answer == "con contesto")
        #expect(model.turns == [QuestionTurn(prompt: "Chi era Volta?", answer: "senza contesto")])
        #expect(model.lastPrompt == "E dove è nato?")
    }

    @Test func newQuestionStartsOver() async {
        await ask("Chi era Volta?")

        model.startNewQuestion()
        #expect(model.turns.isEmpty)
        #expect(model.answer.isEmpty)
        #expect(model.lastPrompt.isEmpty)
        await ask("E dove è nato?")

        #expect(model.answer == "senza contesto")
        #expect(model.turns.isEmpty)
    }

    @Test func fifteenMinutesStillStartOver() async {
        await ask("Chi era Volta?")

        clock.now += QuestionModel.idleLimit
        await ask("E dove è nato?")

        #expect(model.answer == "senza contesto")
        #expect(model.turns.isEmpty)
    }

    @Test func lessThanFifteenMinutesKeepsTheDomanda() async {
        await ask("Chi era Volta?")

        clock.now += QuestionModel.idleLimit - 1
        model.resetIfIdle()
        await ask("E dove è nato?")

        #expect(model.answer == "con contesto")
    }

    @Test func aStillDomandaIsGoneWhenTheBubbleOpens() async {
        await ask("Chi era Volta?")

        clock.now += QuestionModel.idleLimit
        model.resetIfIdle()

        #expect(model.answer.isEmpty)
        #expect(model.lastPrompt.isEmpty)
    }

    @Test func everyTurnGoesToTheSessione() async {
        await ask("Chi era Volta?")
        await ask("E dove è nato?")
        await ask("In che anno?")

        let draft = model.turnIntoSession()

        #expect(draft.turns == [
            QuestionTurn(prompt: "Chi era Volta?", answer: "senza contesto"),
            QuestionTurn(prompt: "E dove è nato?", answer: "con contesto"),
            QuestionTurn(prompt: "In che anno?", answer: "con contesto"),
        ])
        let first = draft.firstPrompt("")
        #expect(first.contains("Chi era Volta?"))
        #expect(first.contains("In che anno?"))
        #expect(first.hasSuffix(String(localized: "Continua da qui, lavorando nel Progetto.")))
    }
}
