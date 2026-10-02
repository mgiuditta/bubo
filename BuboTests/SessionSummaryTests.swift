import Foundation
import Testing
@testable import Bubo

struct SessionSummaryTests {
    @Test func aModelAnswerBecomesTheThreeSections() {
        let summary = SessionSummary(markdown: """
            Ecco il riassunto.

            ## Fatto
            - Aggiunto il filtro dei segreti.
            * Scritti i test.

            ### Decisioni
            1. Il riassunto parte a Fondi.

            ## Aperto

            - Provare Haiku sul Mac.
            """)

        #expect(summary == SessionSummary(done: ["Aggiunto il filtro dei segreti.", "Scritti i test."],
                                          decisions: ["Il riassunto parte a Fondi."],
                                          open: ["Provare Haiku sul Mac."]))
    }

    @Test func aSummaryOverTwoHundredWordsIsCutToTwoHundred() {
        let item = Array(repeating: "parola", count: 30).joined(separator: " ")
        let summary = SessionSummary(done: Array(repeating: item, count: 5), decisions: Array(repeating: item, count: 3),
                                     open: [item])
        #expect(summary.wordCount == 270)

        let limited = summary.limited()

        #expect(limited.wordCount <= SessionSummary.wordLimit)
        #expect(limited.wordCount > SessionSummary.wordLimit - 30)
        #expect(!limited.done.isEmpty && !limited.decisions.isEmpty && !limited.open.isEmpty)
    }

    @Test func aSingleLongItemLosesItsLastWords() {
        let summary = SessionSummary(done: [Array(repeating: "parola", count: 250).joined(separator: " ")])

        #expect(summary.limited().wordCount == SessionSummary.wordLimit)
    }

    @Test func theBodyHasTheThreeSectionsEvenEmpty() {
        let summary = SessionSummary(done: ["Uno."])

        #expect(summary.markdown == """
            ## Fatto

            - Uno.

            ## Decisioni

            Niente.

            ## Aperto

            Niente.

            """)
    }

    @Test func theFrontmatterUsesFaseDatesAndQuotedLinks() {
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        let properties = SummaryProperties(title: "Il \"filtro\"\nnuovo", project: "bubo", branch: nil, phase: .archiviata,
                                           session: id, related: ["Diario", "Idee 2"])

        #expect(properties.frontmatter(createdOn: "2026-10-01", updatedOn: "2026-10-02") == """
            ---
            titolo: "Il \\"filtro\\" nuovo"
            progetto: "bubo"
            fase: archiviata
            creata: 2026-10-01
            aggiornata: 2026-10-02
            sessione: "bubo://sessione/3f2504e0-4f89-11d3-9a0c-0305e82c3301"
            correlate: ["[[Diario]]", "[[Idee 2]]"]
            ---

            """)
    }

    @Test func theInputKeepsTheLatestMessagesOfEveryTurn() {
        let messages = (1...10).map { CLIConversation.Message(isFromUser: $0.isMultiple(of: 2), text: "messaggio \($0) " +
                                                                String(repeating: "x", count: 88)) }
        let input = SummaryInput(session: UUID(), title: "Prova", projectName: "bubo", branch: "bubo/prova",
                                 messages: messages)

        let trimmed = input.trimmed(toCharacters: 350)

        #expect(trimmed.messages.map(\.text) == Array(messages.suffix(3)).map(\.text))
        #expect(trimmed.transcript.contains("Branch: bubo/prova"))
        #expect(trimmed.transcript.contains("[Agente] messaggio 9"))
        #expect(trimmed.transcript.contains("[Utente] messaggio 10"))
    }

    @Test func aVeryLongMessageIsCut() {
        let input = SummaryInput(session: UUID(), title: "Prova", projectName: "bubo", branch: nil,
                                 messages: [CLIConversation.Message(isFromUser: false,
                                                                    text: String(repeating: "y", count: 10_000))])

        #expect(input.trimmed(toCharacters: 40_000).messages.first?.text.count == SummaryInput.messageLimit)
    }
}
