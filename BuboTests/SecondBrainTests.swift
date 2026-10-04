import Foundation
import Testing
@testable import Bubo

/// A Secondo cervello, a `~/.claude` and an Indice in a temporary folder, deleted with the value.
final class NotesFolder {
    let claude: ClaudeFolder
    var notes: URL { claude.folder.appending(path: "Note personali") }

    init() throws {
        claude = try ClaudeFolder()
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    }

    func write(_ text: String, to path: String) throws {
        let file = notes.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Follows `folder` with `index` until the returned task is cancelled.
    func follow(_ folder: URL?, with index: SearchIndex) -> Task<Void, Never> {
        Task { await index.keepSecondBrainFresh(at: folder) }
    }
}

/// Waits up to five seconds for `text` to become findable, or, with `isFound` false, to stop being.
func waitUntil(_ text: String, isFound: Bool = true, in index: SearchIndex, source: SearchSource? = nil) async throws -> Bool {
    for _ in 0..<50 {
        if try await index.hits(for: text, source: source).isEmpty != isFound { return true }
        try await Task.sleep(for: .milliseconds(100))
    }
    return false
}

@Suite(.timeLimit(.minutes(1)))
struct SecondBrainTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    @Test func notesAreFoundButHiddenFoldersSessionSummariesAndOtherFilesStayOut() async throws {
        try folder.write("# Viaggio\n\nPrenotare il traghetto: quokka.", to: "Viaggi/Sardegna.md")
        try folder.write("quokka anche in testo semplice", to: "lista.TXT")
        try folder.write("quokka salvato da Bubo", to: "Bubo/Note/2026-10-01 Quokka.md")
        try folder.write("quokka nelle impostazioni", to: ".obsidian/workspace.md")
        try folder.write("quokka nel cestino", to: ".trash/vecchia.md")
        try folder.write("quokka nascosto", to: "Viaggi/.bozza.md")
        try folder.write("quokka in un riassunto", to: "Bubo/Sessioni/2026-10-01 Sessione.md")
        try folder.write("quokka in un PDF", to: "allegato.pdf")
        try folder.write("quokka fuori dalla cartella", to: "../fuori.md")
        try FileManager.default.createSymbolicLink(at: folder.notes.appending(path: "collegamento.md"),
                                                   withDestinationURL: folder.claude.folder.appending(path: "fuori.md"))
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }

        #expect(try await waitUntil("quokka", in: index))
        let files = try await index.hits(for: "quokka").map { URL(filePath: $0.path).lastPathComponent }
        #expect(Set(files) == ["Sardegna.md", "lista.TXT", "2026-10-01 Quokka.md"])
        #expect(try await index.hits(for: "quokka").allSatisfy { $0.source == .secondBrain && $0.project == nil })
    }

    /// #545: a Riunione is a source, found by `cerca` as soon as it is written; the Riassunti di Sessione stay out.
    @Test func aRiunioneIsFoundAndTheSessionSummariesStayOut() async throws {
        try folder.write("ornitorinco in un riassunto", to: "Bubo/Sessioni/2026-10-01 Sessione.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }

        let note = MeetingNote(title: "Fornitori", start: .now, duration: .seconds(300), app: "Zoom",
                               transcript: [MeetingLine(speaker: .others, start: .seconds(12),
                                                           text: "Il fornitore dell'ornitorinco consegna lunedì.")])
        let written = try NoteWriter(root: folder.notes).writeMeeting(note)

        #expect(try await waitUntil("ornitorinco", in: index))
        let files = try await index.hits(for: "ornitorinco").map { URL(filePath: $0.path).lastPathComponent }
        #expect(Set(files) == [written.file.lastPathComponent])
    }

    @Test func aSourceLimitsTheSearch() async throws {
        try folder.claude.write("deploy dalla memoria", to: "projects/-p/memory/a.md")
        try folder.write("deploy dalle note", to: "a.md")
        let index = try folder.claude.open()
        await index.rescan()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("note", in: index))

        #expect(try await index.hits(for: "deploy").count == 2)
        #expect(try await index.hits(for: "deploy", source: .memory).map(\.source) == [.memory])
        #expect(try await index.hits(for: "deploy", source: .secondBrain).map(\.source) == [.secondBrain])
        // A Progetto has no notes: its search stays in its memory.
        #expect(try await index.hits(for: "deploy", project: "/p").map(\.source) == [.memory])
    }

    @Test func aNoteSavedInBuboNoteIsFoundWithinFiveSeconds() async throws {
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        try await Task.sleep(for: .milliseconds(300))

        try folder.write("Ricordati questo: ornitorinco", to: "Bubo/Note/2026-10-01 Ornitorinco.md")

        #expect(try await waitUntil("ornitorinco", in: index))
    }

    @Test func aFolderDeletedOrRenamedTakesItsNotesAlong() async throws {
        try folder.write("capibara", to: "Archivio/2025/a.md")
        try folder.write("tapiro", to: "Progetti/b.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("capibara", in: index))

        try FileManager.default.removeItem(at: folder.notes.appending(path: "Archivio"))
        try FileManager.default.moveItem(at: folder.notes.appending(path: "Progetti"), to: folder.notes.appending(path: ".nascosti"))

        #expect(try await waitUntil("capibara", isFound: false, in: index))
        #expect(try await waitUntil("tapiro", isFound: false, in: index))
    }

    @Test func aFolderOutOfReachKeepsItsLastCopyAndTheAnswerSaysSo() async throws {
        try folder.write("lontra di mare", to: "a.md")
        let index = try folder.claude.open()
        let first = folder.follow(folder.notes, with: index)
        #expect(try await waitUntil("lontra", in: index))
        first.cancel()
        await first.value

        // As a disk unplugged: the folder is gone, but it was not the user who emptied it.
        let away = folder.claude.folder.appending(path: "scollegato")
        try FileManager.default.moveItem(at: folder.notes, to: away)
        let again = folder.follow(folder.notes, with: index)
        defer { again.cancel() }
        try await Task.sleep(for: .seconds(1.5))

        #expect(try await index.hits(for: "lontra").count == 1)
        let answer = await index.toolResult(for: "lontra", project: nil)
        #expect(answer.hasPrefix("La cartella del Secondo cervello non è raggiungibile"))
        #expect(answer.contains("lontra di mare"))
        #expect(await !index.toolResult(for: "lontra", project: nil, source: .memory).contains("raggiungibile"))

        // The disk plugged in again, with a note written elsewhere meanwhile.
        try "scritta altrove: castoro".write(to: away.appending(path: "b.md"), atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: away, to: folder.notes)
        #expect(try await waitUntil("castoro", in: index))
        #expect(await !index.toolResult(for: "lontra", project: nil).contains("raggiungibile"))
    }

    @Test func anotherFolderReplacesTheNotesAndNoFolderForgetsThem() async throws {
        try folder.write("vecchio vault: fenicottero", to: "a.md")
        let other = folder.claude.folder.appending(path: "Altro")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "nuovo vault: pellicano".write(to: other.appending(path: "b.md"), atomically: true, encoding: .utf8)
        try folder.claude.write("memoria: fenicottero", to: "projects/-p/memory/a.md")
        let index = try folder.claude.open()
        await index.rescan()
        let first = folder.follow(folder.notes, with: index)
        #expect(try await waitUntil("fenicottero", in: index, source: .secondBrain))
        first.cancel()

        let second = folder.follow(other, with: index)
        #expect(try await waitUntil("pellicano", in: index))
        #expect(try await index.hits(for: "fenicottero", source: .secondBrain).isEmpty)
        second.cancel()

        await index.keepSecondBrainFresh(at: nil)
        #expect(try await index.hits(for: "pellicano").isEmpty)
        #expect(try await index.hits(for: "fenicottero", source: .memory).count == 1)
    }

    @Test func noteEditsAreFollowedPerFile() async throws {
        try folder.write("prima versione: gazza", to: "a.md")
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("gazza", in: index))

        try folder.write("seconda versione: upupa", to: "a.md")

        #expect(try await waitUntil("upupa", in: index))
        #expect(try await index.hits(for: "gazza").isEmpty)
    }

    // MARK: Which files are notes

    @Test(arguments: [".obsidian", ".obsidian/app.json", ".trash/a.md", "Diario/.bozza.md", "Bubo/Sessioni",
                      "Bubo/Sessioni/2026-10-01 Sessione.md"])
    func skippedPaths(path: String) {
        #expect(SecondBrainNotes.skips(path))
    }

    @Test(arguments: ["", "Diario/a.md", "Bubo", "Bubo/Note/a.md", "Sessioni/a.md", "Bubo/SessioniVecchie/a.md",
                      "Bubo/Riunioni", "Bubo/Riunioni/2026-10-01 Riunione.md"])
    func readPaths(path: String) {
        #expect(!SecondBrainNotes.skips(path))
    }

    @Test(arguments: [("a.md", true), ("a.MD", true), ("a.txt", true), ("a.pdf", false), ("md", false),
                      ("a.md.png", false), ("Nota senza estensione", false)])
    func notesByName(name: String, isNote: Bool) {
        #expect(SecondBrainNotes.isNote(named: name) == isNote)
    }

    // MARK: Location

    @Test func obsidianVaultsOnThisMacAreSuggestedByName() throws {
        let zettel = folder.claude.folder.appending(path: "Zettel")
        try FileManager.default.createDirectory(at: zettel, withIntermediateDirectories: true)
        let configuration = """
            {"vaults":{"a1":{"path":"\(zettel.path)","ts":1,"open":true},
                       "b2":{"path":"\(folder.notes.path)","ts":2},
                       "c3":{"path":"/nonexistent/Vecchio vault","ts":3}},"frame":{}}
            """

        let vaults = SecondBrainLocation.vaults(inObsidianConfiguration: Data(configuration.utf8))

        #expect(vaults.map(\.lastPathComponent) == ["Note personali", "Zettel"])
    }

    @Test(arguments: ["", "{", #"{"vaults":[]}"#, #"{"altro":{}}"#])
    func anUnexpectedObsidianConfigurationSuggestsNothing(configuration: String) {
        #expect(SecondBrainLocation.vaults(inObsidianConfiguration: Data(configuration.utf8)).isEmpty)
    }

    @Test func theChoiceIsSavedAndForgotten() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainTests-\(UUID().uuidString)"))
        let location = SecondBrainLocation(folder: folder.notes)

        SecondBrainLocation.save(location, in: defaults)
        #expect(SecondBrainLocation.saved(in: defaults) == location)
        SecondBrainLocation.save(nil, in: defaults)
        #expect(SecondBrainLocation.saved(in: defaults) == nil)
    }

    @Test func choosingAndStoppingAreRememberedAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        #expect(secondBrain.location == nil)

        secondBrain.choose(folder.notes)
        #expect(SecondBrain(index: nil, defaults: defaults).location?.name == "Note personali")
        secondBrain.stopUsing()
        #expect(SecondBrain(index: nil, defaults: defaults).location == nil)
    }

    @Test func theBookmarkFollowsAMovedFolder() throws {
        let location = SecondBrainLocation(folder: folder.notes)
        #expect(location.isReachable)
        let moved = folder.claude.folder.appending(path: "Note spostate")
        try FileManager.default.moveItem(at: folder.notes, to: moved)

        #expect(!location.isReachable)
        #expect(location.resolved().url.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
    }

    @Test func aVaultIsRecognisedByItsObsidianFolder() throws {
        #expect(!SecondBrainLocation(folder: folder.notes).isObsidianVault)
        try FileManager.default.createDirectory(at: folder.notes.appending(path: ".obsidian"), withIntermediateDirectories: true)
        #expect(SecondBrainLocation(folder: folder.notes).isObsidianVault)
    }

    // MARK: Excluded folders

    @Test(arguments: ["Archivio", "Archivio/a.md", "Archivio/2025/b.md", "Lavoro/Vecchio/c.md"])
    func anExcludedFolderSkipsEverythingInside(path: String) {
        #expect(SecondBrainNotes.skips(path, excluding: ["Archivio", "Lavoro/Vecchio"]))
    }

    @Test(arguments: ["Archivio2/a.md", "Diario/Archivio.md", "Diario/Archivio/a.md", "Lavoro/a.md"])
    func aNamesakeIsNotExcluded(path: String) {
        #expect(!SecondBrainNotes.skips(path, excluding: ["Archivio", "Lavoro/Vecchio"]))
    }

    @Test func anExcludedFolderLeavesTheIndexAndComesBackWhenIncluded() async throws {
        try folder.write("ornitorinco in archivio", to: "Archivio/2025/a.md")
        try folder.write("ornitorinco nel diario", to: "Diario/b.md")
        let index = try folder.claude.open()
        var following = folder.follow(folder.notes, with: index)
        #expect(try await waitUntil("archivio", in: index))

        following.cancel()
        following = Task { await index.keepSecondBrainFresh(at: folder.notes, excluding: ["Archivio"]) }
        #expect(try await waitUntil("archivio", isFound: false, in: index))
        #expect(try await index.hits(for: "ornitorinco").count == 1)

        following.cancel()
        following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("archivio", in: index))
    }

    @Test func anExclusionChangedWhileClosedAppliesAtTheNextStart() async throws {
        try folder.write("ornitorinco in archivio", to: "Archivio/a.md")
        var index = try folder.claude.open()
        let first = folder.follow(folder.notes, with: index)
        #expect(try await waitUntil("archivio", in: index))
        first.cancel()
        await first.value

        index = try folder.claude.open()
        let second = Task { [index] in await index.keepSecondBrainFresh(at: folder.notes, excluding: ["Archivio"]) }
        defer { second.cancel() }
        #expect(try await waitUntil("archivio", isFound: false, in: index))
    }

    @Test func beyondTheLimitTheLoadNamesTheLargestFolders() async throws {
        for (folderName, count) in [("Grande", 4), ("Media", 2), ("Piccola", 1)] {
            for number in 0..<count {
                try folder.write("nota \(number)", to: "\(folderName)/\(number).md")
            }
        }
        try folder.write("nota in cima", to: "cima.md")
        let index = try folder.claude.open(fragmentLimit: 5)
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }
        #expect(try await waitUntil("cima", in: index))

        let load = try await index.fragmentLoad(largest: 2)

        #expect(load.exceedsLimit)
        #expect(load.fragmentCount == 8)
        #expect(load.largestFolders == [FolderLoad(relativePath: "Grande", fragmentCount: 4),
                                        FolderLoad(relativePath: "Media", fragmentCount: 2)])
    }

    @Test(arguments: [(100_000, false), (100_001, true)])
    func theLimitIsOneHundredThousandFragments(count: Int, exceeds: Bool) {
        #expect(FragmentLoad(fragmentCount: count, limit: SearchIndex.fragmentLimit, largestFolders: []).exceedsLimit == exceeds)
    }

    @Test func exclusionsAreRememberedAndAnotherFolderStartsWithout() throws {
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)

        try secondBrain.exclude(folder.notes.appending(path: "Archivio/2025"))
        try secondBrain.exclude(folder.notes.appending(path: "Allegati"))
        #expect(SecondBrain(index: nil, defaults: defaults).location?.excludedFolders == ["Allegati", "Archivio/2025"])
        secondBrain.include("Allegati")
        #expect(SecondBrain(index: nil, defaults: defaults).location?.excludedFolders == ["Archivio/2025"])

        secondBrain.choose(folder.claude.folder)
        #expect(SecondBrain(index: nil, defaults: defaults).location?.excludedFolders == [])
    }

    @Test func aFolderOutsideTheSecondBrainCannotBeExcluded() throws {
        let secondBrain = SecondBrain(index: nil, defaults: try #require(UserDefaults(suiteName: "SecondBrainTests-\(UUID().uuidString)")))
        secondBrain.choose(folder.notes)

        #expect(throws: SecondBrainExclusionError.outsideSecondBrain) { try secondBrain.exclude(folder.claude.folder) }
        #expect(throws: SecondBrainExclusionError.outsideSecondBrain) { try secondBrain.exclude(folder.notes) }
    }

    @Test func aChoiceSavedBeforeExclusionsStillLoads() throws {
        let saved = #"{"path":"/Users/prova/Note"}"#

        let location = try JSONDecoder().decode(SecondBrainLocation.self, from: Data(saved.utf8))

        #expect(location.path == "/Users/prova/Note")
        #expect(location.excludedFolders.isEmpty)
    }

    @Test func aMovedFolderKeepsItsExclusions() throws {
        var location = SecondBrainLocation(folder: folder.notes)
        location.excludedFolders = ["Archivio"]
        try FileManager.default.moveItem(at: folder.notes, to: folder.claude.folder.appending(path: "Note spostate"))

        #expect(location.resolved().excludedFolders == ["Archivio"])
    }
}
