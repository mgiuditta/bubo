import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct AnswerBlockTests {
    @Test func codeBetweenFencesIsItsOwnBlockWithoutTheFences() {
        let answer = "Ecco:\n\n```swift\nlet a = 1\n\nprint(a)\n```\n\nFatto."

        #expect(AnswerBlock.blocks(of: answer) == [.prose("Ecco:"), .code("let a = 1\n\nprint(a)"), .prose("Fatto.")])
    }

    @Test func aFenceStillOpenWhileStreamingRunsToTheEnd() {
        #expect(AnswerBlock.blocks(of: "Ecco:\n```py\nprint(1)\npri") == [.prose("Ecco:"), .code("print(1)\npri")])
        #expect(AnswerBlock.blocks(of: "Ecco:\n```") == [.prose("Ecco:"), .code("")])
    }

    @Test func aFenceWithALanguageDoesNotCloseABlock() {
        #expect(AnswerBlock.blocks(of: "```\na\n```js\nb\n```") == [.code("a\n```js\nb")])
    }

    @Test func anAnswerWithoutCodeIsOneProseBlock() {
        #expect(AnswerBlock.blocks(of: "Una riga\n- uno\n- due") == [.prose("Una riga\n- uno\n- due")])
        #expect(AnswerBlock.blocks(of: "").isEmpty)
    }

    @Test func inlineMarkdownIsAppliedAndTheTextKeepsItsLines() {
        let formatted = AnswerBlock.formatted("**forte** e *corsivo*, `codice` e [sito](https://example.com)\n- voce")

        #expect(String(formatted.characters) == "forte e corsivo, codice e sito\n- voce")
        #expect(formatted.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(formatted.runs.contains { $0.inlinePresentationIntent == .emphasized })
        #expect(formatted.runs.contains { $0.inlinePresentationIntent == .code })
        #expect(formatted.runs.compactMap(\.link) == [URL(string: "https://example.com")])
    }

    @Test func aHeadingIsBoldWithoutItsHashes() {
        let formatted = AnswerBlock.formatted("## Passi\nprimo")

        #expect(String(formatted.characters) == "Passi\nprimo")
        #expect(formatted.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test func aWikilinkStaysALinkToItsNoteEvenWithMarkdownInItsName() {
        let formatted = AnswerBlock.formatted("Vedi **[[Ricette/pane_di_casa#Impasto]]** e [[Standup]].")

        #expect(String(formatted.characters) == "Vedi pane_di_casa · Impasto e Standup.")
        let citations = formatted.runs.compactMap(\.link).compactMap(NoteCitation.init(link:))
        #expect(citations == [NoteCitation(note: "Ricette/pane_di_casa", anchor: "Impasto"), NoteCitation(note: "Standup")])
    }

    @Test func ofTheModelsLinksOnlyTheWebOnesStayLinksAndANoteOpensOnlyFromAWikilink() {
        let formatted = AnswerBlock.formatted(
            "[a](file:///etc/passwd) [b](bubo-nota://apri?nota=Segreti) [c](x-apple.systempreferences:x) [d](https://ok) [[Pane]]"
        )

        #expect(String(formatted.characters) == "a b c d Pane")
        #expect(formatted.runs.compactMap(\.link) == [URL(string: "https://ok"), NoteCitation(note: "Pane").link])
    }

    @Test func markdownCutShortWhileStreamingStaysAsWritten() {
        #expect(String(AnswerBlock.formatted("Un **grassetto a metà").characters) == "Un **grassetto a metà")
        #expect(String(AnswerBlock.formatted("Vedi [[Pane").characters) == "Vedi [[Pane")
    }
}
