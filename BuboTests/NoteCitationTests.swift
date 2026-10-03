import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct NoteCitationTests {
    @Test(arguments: [
        ("Ricette/Pane", NoteCitation(note: "Ricette/Pane")),
        ("2026-10-03 Standup#12:40", NoteCitation(note: "2026-10-03 Standup", anchor: "12:40")),
        ("Pane|il pane di casa", NoteCitation(note: "Pane")),
        ("Pane#", NoteCitation(note: "Pane")),
    ])
    func aWikilinkNamesItsNoteAndWhereInIt(inner: String, citation: NoteCitation) {
        #expect(NoteCitation(wikilink: inner) == citation)
    }

    @Test func anEmptyWikilinkCitesNothing() {
        #expect(NoteCitation(wikilink: "") == nil)
        #expect(NoteCitation(wikilink: "#12:40") == nil)
    }

    @Test func theLinkCarriesTheCitationAndOnlyItsOwn() throws {
        let citation = NoteCitation(note: "Bubo/Riunioni/2026-10-03 Standup & co", anchor: "12:40")
        #expect(NoteCitation(link: citation.link) == citation)
        #expect(NoteCitation(link: try #require(URL(string: "https://example.com/?nota=x"))) == nil)
    }

    @Test func aNoteInsideTheSecondBrainIsCitedByItsPathWithoutMarkdownExtension() {
        #expect(NoteCitation(path: "/v/Bubo/Riunioni/Standup.md", inFolder: "/v") == NoteCitation(note: "Bubo/Riunioni/Standup"))
        #expect(NoteCitation(path: "/v/lista.txt", inFolder: "/v/") == NoteCitation(note: "lista.txt"))
        #expect(NoteCitation(path: "/altrove/a.md", inFolder: "/v") == nil)
    }

    @Test func theAnswerShowsCitationsAsLinksAndKeepsTheRestAsWritten() throws {
        let answer = "Il pane lievita 8 ore [[Ricette/Pane]]; deciso alle [[Standup#12:40]]. Niente [[ qui\n]] né [[]]."
        let linked = NoteCitation.linking(answer)

        #expect(String(linked.characters) == "Il pane lievita 8 ore Pane; deciso alle Standup · 12:40. Niente [[ qui\n]] né [[]].")
        let links = linked.runs.compactMap(\.link).compactMap(NoteCitation.init(link:))
        #expect(links == [NoteCitation(note: "Ricette/Pane"), NoteCitation(note: "Standup", anchor: "12:40")])
    }

    @Test func aCitedNoteIsFoundByPathOrByNameButNeverOutsideTheFolder() throws {
        let folder = try NotesFolder()
        try folder.write("pane", to: "Ricette/Pane.md")
        try folder.write("pane vecchio", to: "Archivio/2025/Pane.md")
        try folder.write("lista", to: "lista.txt")
        try folder.write("fuori", to: "../Fuori.md")

        #expect(NoteCitation(note: "Archivio/2025/Pane").file(inFolder: folder.notes)?.lastPathComponent == "Pane.md")
        #expect(NoteCitation(note: "Archivio/2025/Pane").file(inFolder: folder.notes)?.path.contains("2025") == true)
        #expect(NoteCitation(note: "pane").file(inFolder: folder.notes)?.path.contains("Ricette") == true)
        #expect(NoteCitation(note: "lista.txt").file(inFolder: folder.notes) != nil)
        #expect(NoteCitation(note: "../Fuori").file(inFolder: folder.notes) == nil)
        #expect(NoteCitation(note: "Assente").file(inFolder: folder.notes) == nil)
    }

    @Test func aNoteOpensInObsidianOnlyForAVaultWithObsidianOnTheMac() throws {
        let file = URL(filePath: "/v/Ricette/Pane al latte.md")
        let link = try #require(NoteDestination.obsidianLink(to: file))

        #expect(link.absoluteString == "obsidian://open?path=/v/Ricette/Pane%20al%20latte.md")
        #expect(NoteDestination(file: file, isObsidianVault: true, hasObsidian: true) == .obsidian(link))
        #expect(NoteDestination(file: file, isObsidianVault: true, hasObsidian: false) == .quickLook(file))
        #expect(NoteDestination(file: file, isObsidianVault: false, hasObsidian: true) == .quickLook(file))
    }

    @Test func theAnswerToCercaGivesEachNoteItsCitationAndAsksToCiteThem() async throws {
        let folder = try NotesFolder()
        try folder.write("Alle 12:40 si decide il rilascio: ornitorinco.", to: "Bubo/Riunioni/2026-10-03 Standup.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("ornitorinco", in: index))

        let answer = await index.toolResult(for: "ornitorinco", project: nil)

        #expect(answer.contains("(Cita come [[Bubo/Riunioni/2026-10-03 Standup]])"))
        #expect(answer.hasSuffix(SearchIndex.citationRule))
    }
}
