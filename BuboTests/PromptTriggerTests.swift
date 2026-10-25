import Foundation
import Testing
@testable import Bubo

/// The sentences of a Riunione the Suggeritore answers, and those it lets go by.
nonisolated struct PromptTriggerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func line(_ text: String, by speaker: MeetingLine.Speaker) -> MeetingLine {
        MeetingLine(speaker: speaker, start: nil, text: text)
    }

    @Test(arguments: [
        ("Ma cosa avevamo deciso sul rilascio di lunedì?", MeetingLine.Speaker.others),
        ("Chi doveva fare la revisione dei buoni?", .others),
        ("Quando è stato approvato il budget?", .others),
        ("Ti ricordi cosa ci aveva detto Daniele?", .me),
        ("Come eravamo rimasti con il fornitore?", .others),
        ("What did we decide about the release?", .others),
        ("Non so, non mi ricordo qual è l'ultimo ticket di Savi.", .me),
        ("A che punto è la migrazione del carrello?", .others),
    ])
    func answersQuestionsAboutThePast(text: String, speaker: MeetingLine.Speaker) {
        var trigger = PromptTrigger()
        let question = trigger.question(in: Self.line(text, by: speaker), at: start)
        #expect(question == PromptTrigger.Question(text: text, reason: .pastQuestion))
    }

    @Test(arguments: [
        "Oggi facciamo il punto sullo sprint.",
        "Va bene?",
        "Quando hai tempo guardiamo la merge request.",
    ])
    func letsOtherSentencesGoBy(text: String) {
        var trigger = PromptTrigger()
        #expect(trigger.question(in: Self.line(text, by: .others), at: start) == nil)
    }

    @Test func answersARepeatedQuestionOnce() {
        var trigger = PromptTrigger()
        let line = Self.line("Chi doveva fare la revisione?", by: .others)
        #expect(trigger.question(in: line, at: start) != nil)
        #expect(trigger.question(in: line, at: start + 10) == nil)
        #expect(trigger.question(in: line, at: start + 40) != nil)
    }

    @Test func findsTheLastQuestionHeard() {
        var trigger = PromptTrigger()
        _ = trigger.question(in: Self.line("Senti, chi segue il fornitore nuovo?", by: .others), at: start)
        _ = trigger.question(in: Self.line("Adesso controllo.", by: .me), at: start + 2)
        #expect(trigger.lastQuestion(at: start + 5)
            == PromptTrigger.Question(text: "Senti, chi segue il fornitore nuovo?", reason: .lastQuestion))
        #expect(trigger.lastQuestion(at: start + 120) == nil)
    }
}
