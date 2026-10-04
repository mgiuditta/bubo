import Foundation
import Testing
@testable import Bubo

/// The suggestions of the empty home, from the notes changed last.
struct HomeSuggestionsTests {
    @Test func atMostThreeSuggestionsFromTheNotes() {
        let suggestions = HomeSuggestions.make(recentNotes: ["Lancio", "Riunione 3 ottobre", "Idee", "Budget"])
        #expect(suggestions.count == 3)
        #expect(suggestions.first == String(localized: "Cosa c'è di nuovo in \("Lancio")?"))
    }

    @Test func withoutNotesThereAreGeneralOnes() {
        #expect(HomeSuggestions.make(recentNotes: []).count == 3)
    }

    @Test func theNotesChangedLastComeFirstAndBubosFolderIsLeftOut() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cervello-\(UUID().uuidString)",
                                                                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Bubo"), withIntermediateDirectories: true)
        for (index, name) in ["Vecchia", "Media", "Nuova"].enumerated() {
            let file = folder.appending(path: "\(name).md")
            try Data("# \(name)".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index) * 1000)],
                                                  ofItemAtPath: file.path)
        }
        try Data("profilo".utf8).write(to: folder.appending(path: "Bubo/Profilo.md"))
        try Data("x".utf8).write(to: folder.appending(path: "foto.png"))
        #expect(await HomeSuggestions.recentNotes(in: folder) == ["Nuova", "Media", "Vecchia"])
    }
}
