import Foundation
import Testing
@testable import Bubo

/// `cerca` without the Indice: the notes searched by words, straight in the folder.
struct WordSearchTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    @Test func aNoteIsFoundByAnExactWordWithItsCitation() throws {
        try folder.write("# Viaggio\n\nPrenotare il traghetto per Olbia.\nAltro.", to: "Viaggi/Sardegna.md")
        try folder.write("Niente di utile.", to: "Altro.md")

        let answer = WordSearch.toolResult(for: "traghetto", in: folder.notes.path)

        #expect(answer.contains("(Cita come [[Viaggi/Sardegna]])"))
        #expect(answer.contains("Prenotare il traghetto per Olbia."))
        #expect(!answer.contains("Altro.md"))
    }

    @Test func caseAndAccentsAreIgnored() throws {
        try folder.write("Perché così.", to: "Riunione.md")

        #expect(WordSearch.toolResult(for: "PERCHE", in: folder.notes.path).contains("[[Riunione]]"))
    }

    @Test func excludedFoldersStayOut() throws {
        try folder.write("quokka privato", to: "Diario/oggi.md")
        try folder.write("quokka nascosto", to: ".obsidian/workspace.md")
        try folder.write("quokka pubblico", to: "Note/zoo.md")

        let answer = WordSearch.toolResult(for: "quokka", in: folder.notes.path, excluding: ["Diario"])

        #expect(answer.contains("[[Note/zoo]]"))
        #expect(!answer.contains("Diario"))
        #expect(!answer.contains(".obsidian"))
    }

    @Test func nothingFoundSaysSo() throws {
        try folder.write("Solo questo.", to: "Nota.md")

        #expect(WordSearch.toolResult(for: "ornitorinco", in: folder.notes.path) == SearchIndex.noResults)
    }

    @MainActor @Test func cercaFallsBackToWordsWithoutTheIndice() async throws {
        try folder.write("quokka pubblico", to: "Note/zoo.md")
        try folder.write("quokka privato", to: "Diario/oggi.md")
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        try secondBrain.exclude(folder.notes.appending(path: "Diario"))
        let model = QuestionModel(index: nil, secondBrain: secondBrain)

        let answer = await model.searchResult(for: "quokka", project: nil, source: nil)

        #expect(answer.contains("[[Note/zoo]]"))
        #expect(!answer.contains("Diario"))
        #expect(await model.searchResult(for: "quokka", project: nil, source: .memory) == "L'Indice non è disponibile.")
    }
}
