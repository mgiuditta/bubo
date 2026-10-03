import Foundation
import Testing
@testable import Bubo

/// The answers of the guided setup of the Secondo cervello, and the clarifying question when notes look alike (#554).
@Suite(.timeLimit(.minutes(1)))
struct SecondBrainProfileTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    @Test func priorityFoldersComeFirstInCerca() async throws {
        try folder.write("ornitorinco ornitorinco ornitorinco ornitorinco", to: "Archivio/a.md")
        try folder.write("un ornitorinco al lavoro, in mezzo a tante altre parole della nota", to: "Lavoro/b.md")
        try folder.write("un ornitorinco omonimo, in mezzo a tante altre parole della nota", to: "Lavoro2/c.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        for word in ["lavoro", "omonimo"] { #expect(try await waitUntil(word, in: index)) }
        let before = try await index.hits(for: "ornitorinco").map(\.path)
        #expect(before.first?.hasSuffix("Archivio/a.md") == true)

        await index.prioritize(["Lavoro"])
        let after = try await index.hits(for: "ornitorinco").map(\.path)

        #expect(after.count == 3)
        #expect(after.first?.hasSuffix("Lavoro/b.md") == true)
        #expect(Array(after.dropFirst()) == before.filter { !$0.hasSuffix("Lavoro/b.md") })
    }

    @Test func theProfileIsSavedAndAnExcludedFolderIsNoLongerFirst() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainProfileTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)

        try secondBrain.prioritize(folder.notes.appending(path: "Lavoro"))
        secondBrain.prioritizeOnly(["Lavoro", "Progetti/Bubo"])
        #expect(SecondBrain(index: nil, defaults: defaults).location?.priorityFolders == ["Lavoro", "Progetti/Bubo"])

        secondBrain.excludeOnly(["Lavoro", "Archivio"])
        let saved = SecondBrain(index: nil, defaults: defaults).location
        #expect(saved?.excludedFolders == ["Archivio", "Lavoro"])
        #expect(saved?.priorityFolders == ["Progetti/Bubo"])
        #expect(throws: SecondBrainExclusionError.outsideSecondBrain) { try secondBrain.prioritize(folder.claude.folder) }
    }

    @Test func theSetupOffersTheFoldersAtTheTopButNotHiddenOnesOrBubo() throws {
        for path in ["Lavoro/a.md", "archivio/b.md", ".obsidian/c.md", "Bubo/Note/d.md", "cima.md"] {
            try folder.write("nota", to: path)
        }

        #expect(SecondBrainLocation(folder: folder.notes).topFolders() == ["archivio", "Lavoro"])
    }

    @Test func notesSharingATitleOnDifferentDaysAreOneGroup() {
        let notes = ["Ricette/Pane", "Bubo/Riunioni/2026-10-02 Standup", "Bubo/Riunioni/2026-10-02 Standup",
                     "Bubo/Riunioni/2026-10-03 Standup", "Diario/2026-10-02", "Diario/2026-10-03"]

        #expect(SimilarNotes.firstGroup(among: notes) == ["Bubo/Riunioni/2026-10-02 Standup",
                                                          "Bubo/Riunioni/2026-10-03 Standup"])
        #expect(SimilarNotes.firstGroup(among: ["Ricette/Pane", "Ricette/Pizza", "Diario/2026-10-02",
                                                "Diario/2026-10-03"]) == nil)
    }

    @Test func cercaAsksOneQuestionWithTheRealOptionsWhenNotesLookAlike() async throws {
        try folder.write("Standup: si parla del rilascio, quokka.", to: "Riunioni/2026-10-02 Standup.md")
        try folder.write("Standup: il rilascio slitta, quokka.", to: "Riunioni/2026-10-03 Standup.md")
        try folder.write("Una ricetta con il quokka.", to: "Ricette/Pane.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        for word in ["slitta", "parla", "ricetta"] { #expect(try await waitUntil(word, in: index)) }

        let answer = await index.toolResult(for: "quokka", project: nil)
        let alone = await index.toolResult(for: "ricetta", project: nil)

        #expect(answer.contains("[[Riunioni/2026-10-02 Standup]], [[Riunioni/2026-10-03 Standup]] sembrano")
            || answer.contains("[[Riunioni/2026-10-03 Standup]], [[Riunioni/2026-10-02 Standup]] sembrano"))
        #expect(answer.contains("una sola domanda"))
        #expect(answer.hasSuffix(SearchIndex.citationRule))
        #expect(!alone.contains("una sola domanda"))
    }

    @Test func peopleAndProjectsOfTheProfileComeFirstInCerca() async throws {
        try folder.write("lemure lemure lemure lemure", to: "Note/a.md")
        try folder.write("un lemure citato da Giulia Rossì, in mezzo a tante altre parole della nota", to: "Note/b.md")
        try folder.write("un lemure per il progetto Quasar, in mezzo a tante altre parole della nota", to: "Note/c.md")
        try folder.write("un lemure adattato da Giulia, in mezzo a tante altre parole della nota", to: "Note/d.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        for word in ["citato", "quasar", "adattato"] { #expect(try await waitUntil(word, in: index)) }
        let before = try await index.hits(for: "lemure").map(\.path)
        #expect(before.first?.hasSuffix("Note/a.md") == true)

        await index.prioritize([], names: ["giulia rossi", "Quasar", "Ada"])
        let after = try await index.hits(for: "lemure").map(\.path)

        let named = after.prefix(2).map { ($0 as NSString).lastPathComponent }
        #expect(Set(named) == ["b.md", "c.md"])
        #expect(Array(after.dropFirst(2)) == before.filter { !$0.hasSuffix("b.md") && !$0.hasSuffix("c.md") })
    }

    @Test func priorityFoldersComeBeforeTheNamesOfTheProfile() async throws {
        try folder.write("un capibara per Quasar, in mezzo a tante altre parole della nota", to: "Archivio/a.md")
        try folder.write("un capibara qualunque, in mezzo a tante altre parole della nota", to: "Lavoro/b.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        for word in ["quasar", "qualunque"] { #expect(try await waitUntil(word, in: index)) }

        await index.prioritize(["Lavoro"], names: ["Quasar"])
        let hits = try await index.hits(for: "capibara").map(\.path)

        #expect(hits.count == 2)
        #expect(hits.first?.hasSuffix("Lavoro/b.md") == true)
    }

    @Test func thePeopleAndProjectsAreSavedInTheProfile() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainProfileTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)

        secondBrain.prioritize(people: SecondBrainLocation.names(in: " Giulia Rossi, marco,,Marco , "),
                               projects: SecondBrainLocation.names(in: "Bubo"))

        let saved = SecondBrain(index: nil, defaults: defaults).location
        #expect(saved?.people == ["Giulia Rossi", "marco"])
        #expect(saved?.projects == ["Bubo"])
    }

    @Test func aRiunioneProposesFirstTheAppOfTheChosenServices() {
        let apps = [MeetingApp(name: "Note", bundleID: "com.apple.Notes"),
                    MeetingApp(name: "Safari", bundleID: "com.apple.Safari"),
                    MeetingApp(name: "Zoom", bundleID: "us.zoom.xos")]

        #expect(CallService.preferredApp(among: apps, services: [.meet])?.name == "Safari")
        #expect(CallService.preferredApp(among: apps, services: [])?.name == "Safari")
        #expect(CallService.preferredApp(among: apps, services: [.teams, .zoom])?.name == "Zoom")
        #expect(CallService.preferredApp(among: Array(apps.prefix(1)), services: [.zoom]) == nil)
    }

    @Test func theAnswersAboutTheRiunioniAreSaved() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainProfileTests-\(UUID().uuidString)"))
        #expect(MeetingLanguage.saved(in: defaults) == .current)
        #expect(CallService.saved(in: defaults).isEmpty)

        defaults.set("en", forKey: MeetingLanguage.defaultsKey)
        CallService.save([.teams, .zoom], in: defaults)

        #expect(MeetingLanguage.saved(in: defaults).identifier == "en")
        #expect(CallService.saved(in: defaults) == [.zoom, .teams])
    }
}
