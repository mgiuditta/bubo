import Foundation
import Synchronization
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

    // #668: Comandi rapidi, Spotlight or another app ask a new Domanda; the Bolla's turns stay out of it.
    @Test func anAskFromOutsideStartsANewDomanda() async {
        await ask("Chi era Volta?")
        model.prompt = "sto scrivendo"

        model.ask("E dove è nato?", attachments: [])
        #expect(model.turns.isEmpty)
        await model.answering?.value

        #expect(model.answer == "senza contesto")
        #expect(model.turns.isEmpty)
        #expect(model.lastPrompt == "E dove è nato?")
        #expect(model.prompt == "sto scrivendo")
    }

    /// Answers on the Mac with "Como.", and keeps each question it reads.
    nonisolated final class RecordingAnswerer: OnDeviceAnswering {
        let questions = Mutex<[String]>([])

        func answer(to question: String, attachments: [Allegato]) -> AsyncThrowingStream<String, any Error> {
            questions.withLock { $0.append(question) }
            return AsyncThrowingStream { continuation in
                continuation.yield("Como.")
                continuation.finish()
            }
        }
    }

    /// A model whose router keeps every Domanda on the Mac, with `answerer`, unless the chip picks another model.
    func modelOnTheMac(answering answerer: RecordingAnswerer) throws -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let rules = RuleClassifier(catalogo: try Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: .fitting) {
            RequestClassifier(engines: [QuestionModelTests.FixedEngine(type: .shortFact)], rules: rules)
        }
        let clock = clock
        return QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", Self.bridge], defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             onDeviceAnswerer: answerer, now: { clock.now })
    }

    // #668: what was asked and answered on the Mac does not leave it when a seguito goes to a cloud.
    @Test func aTurnOnTheMacDoesNotFollowASeguitoToClaude() async throws {
        let answerer = RecordingAnswerer()
        let model = try modelOnTheMac(answering: answerer)
        model.prompt = "Chi era Volta?"
        model.ask()
        await model.answering?.value
        #expect(model.answer == "Como.")
        #expect(model.routedAnswer?.isOnMac == true)

        model.choose(Route(family: .sonnet, model: "sonnet", effort: nil, reason: .chosenByUser))
        model.prompt = "E dove è nato?"
        model.ask()
        await model.answering?.value

        #expect(model.answer == "senza contesto")
        #expect(model.turns == [QuestionTurn(prompt: "Chi era Volta?", answer: "Como.", isOnMac: true)])
    }

    @Test func aSeguitoOnTheMacStillReadsTheTurnsOnTheMac() async throws {
        let answerer = RecordingAnswerer()
        let model = try modelOnTheMac(answering: answerer)
        model.prompt = "Chi era Volta?"
        model.ask()
        await model.answering?.value

        model.prompt = "E dove è nato?"
        model.ask()
        await model.answering?.value

        let questions = answerer.questions.withLock { $0 }
        #expect(questions.count == 2)
        #expect(questions.last?.contains("Chi era Volta?") == true)
    }

    @Test func aTurnInTheCloudStillFollowsASeguitoToTheCloud() {
        let turns = [
            QuestionTurn(prompt: "Sul Mac", answer: "Sì", isOnMac: true),
            QuestionTurn(prompt: "Nel cloud", answer: "Sì"),
        ]

        #expect(QuestionTurn.leavingTheMac(turns) == [QuestionTurn(prompt: "Nel cloud", answer: "Sì")])
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
