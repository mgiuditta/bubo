import Testing
@testable import Bubo

/// The Sintesi parlata picked out of an answer as it streams (spec 08).
struct SpokenSummaryTests {
    /// What `chunks` show, and the Sintesi parlata they give, read as they stream.
    func read(_ chunks: [String]) -> (shown: String, line: String?, knownAfter: Int?) {
        var summary = SpokenSummary()
        var shown = ""
        var knownAfter: Int?
        for (index, chunk) in chunks.enumerated() {
            shown += summary.read(chunk)
            if knownAfter == nil, summary.line != nil { knownAfter = index }
        }
        shown += summary.finish()
        return (shown, summary.line, knownAfter)
    }

    @Test func theDedicatedLineIsSaidAndNotShown() {
        let answer = read(["Sinte", "si parlata: Lima è sette", " ore indietro.\n\n", "Ecco i dettagli: …"])
        #expect(answer.line == "Lima è sette ore indietro.")
        #expect(answer.shown == "Ecco i dettagli: …")
        // Known at the end of its line, before the rest of the answer.
        #expect(answer.knownAfter == 2)
    }

    @Test func withoutTheLineTheFirstTwoSentencesAreSaidAndAllIsShown() {
        let text = "Sì, si può. Basta un comando. Poi il resto della spiegazione."
        let answer = read([text])
        #expect(answer.line == "Sì, si può. Basta un comando.")
        #expect(answer.shown == text)
    }

    @Test func codeAndTablesAreNotSaid() {
        let text = """
            ## Risposta
            ```swift
            let x = 3.5. Altro.
            ```
            | a | b |
            - Usa `git status`. Poi controlla il **ramo**.
            """
        let answer = read([text])
        #expect(answer.line == "Usa git status. Poi controlla il ramo.")
        #expect(answer.shown == text)
    }

    @Test func aDecimalPointDoesNotEndASentence() {
        #expect(SpokenSummary.firstSentences(of: "Costa 3.5 euro. Va bene. Altro", isComplete: false)
            == "Costa 3.5 euro. Va bene.")
    }

    @Test func aShortAnswerIsSaidWhole() {
        let answer = read(["Quattro"])
        #expect(answer.line == "Quattro")
        #expect(answer.shown == "Quattro")
    }

    @Test func anEmptyLineFallsBackOnTheProse() {
        let answer = read(["Sintesi parlata:\n", "Primo. Secondo. Terzo."])
        #expect(answer.line == "Primo. Secondo.")
        #expect(answer.shown == "Primo. Secondo. Terzo.")
    }

    @Test func aLineWithNoEndIsSaidAtTheEnd() {
        let answer = read(["Sintesi parlata: Fatto"])
        #expect(answer.line == "Fatto")
        #expect(answer.shown.isEmpty)
    }
}
