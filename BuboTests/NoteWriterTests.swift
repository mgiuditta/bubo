import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct NoteWriterTests {
    let folder: NotesFolder
    /// 1 October 2026, 00:30 in Rome: still 30 September in UTC, so the date must be Rome's.
    nonisolated static let day = Date(timeIntervalSince1970: 1_790_807_400)
    static let rome = TimeZone(identifier: "Europe/Rome")!

    init() throws {
        folder = try NotesFolder()
    }

    var writer: NoteWriter {
        NoteWriter(root: folder.notes, timeZone: Self.rome, now: { Self.day })
    }

    /// Every file and folder under the Secondo cervello, as paths relative to it.
    func contents() throws -> Set<String> {
        Set(try FileManager.default.subpathsOfDirectory(atPath: folder.notes.path))
    }

    @Test func aNoteGoesInBuboNoteWithTheDateTheTitleAndPropertiesForObsidian() throws {
        let note = try writer.remember("Il codice del cancello è 4521.\n", titled: "Cancello di casa")

        #expect(note.file.path == folder.notes.appending(path: "Bubo/Note/2026-10-01 Cancello di casa.md").path)
        #expect(try String(contentsOf: note.file, encoding: .utf8) == """
            ---
            titolo: "Cancello di casa"
            creata: 2026-10-01
            fonte: Domanda
            ---

            Il codice del cancello è 4521.

            """)
    }

    @Test func nothingIsTouchedOutsideBubo() throws {
        try folder.write("# Diario", to: "Diario/oggi.md")
        let before = try contents()

        _ = try writer.remember("a", titled: "Uno")
        _ = try writer.remember("b", titled: "../../Fuori")

        let added = try contents().subtracting(before)
        #expect(added == ["Bubo", "Bubo/Note", "Bubo/Note/2026-10-01 Uno.md", "Bubo/Note/2026-10-01 Fuori.md"])
        #expect(try String(contentsOf: folder.notes.appending(path: "Diario/oggi.md"), encoding: .utf8) == "# Diario")
    }

    @Test func aTakenNameGetsANumberAndTheFirstNoteStaysAsItWas() throws {
        let first = try writer.remember("prima", titled: "Idea")
        let second = try writer.remember("seconda", titled: "Idea")

        #expect(second.file.lastPathComponent == "2026-10-01 Idea 2.md")
        #expect(first.isUnchanged)
        #expect(try String(contentsOf: first.file, encoding: .utf8).contains("prima"))
    }

    @Test func aNoteEditedByHandIsNoLongerTheOneBuboWrote() throws {
        let note = try writer.remember("testo", titled: "Nota")
        #expect(note.isUnchanged)

        try "testo cambiato a mano".write(to: note.file, atomically: true, encoding: .utf8)

        #expect(!note.isUnchanged)
    }

    @Test(arguments: [
        ("Cancello di casa", "Cancello di casa"),
        ("a/b:c*d?e\"f<g>h|i\\j", "a b c d e f g h i j"),
        ("[[Link]] #tag ^blocco", "Link tag blocco"),
        ("riga\nseconda\triga", "riga seconda riga"),
        ("../../.nascosta", "nascosta"),
        ("  ", "Nota"),
        ("///", "Nota"),
        (String(repeating: "a", count: 200), String(repeating: "a", count: 80)),
    ])
    func titlesBecomeSafeFileNames(title: String, name: String) {
        #expect(NoteWriter.fileName(for: title) == name)
    }

    @Test func aFolderOutOfReachWritesNothing() throws {
        let gone = NoteWriter(root: folder.notes.appending(path: "Scollegato"))

        #expect(throws: NoteWriter.Failure.unreachable) {
            try gone.remember("testo", titled: "Nota")
        }
        #expect(!FileManager.default.fileExists(atPath: folder.notes.appending(path: "Scollegato").path))
    }

    @Test func aBuboFolderLinkedElsewhereWritesNothingThere() throws {
        let elsewhere = folder.claude.folder.appending(path: "Altrove")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.notes.appending(path: "Bubo"), withDestinationURL: elsewhere)

        #expect(throws: NoteWriter.Failure.outsideBubo) {
            try writer.remember("testo", titled: "Nota")
        }
        let written = try FileManager.default.subpathsOfDirectory(atPath: elsewhere.path)
        #expect(written.allSatisfy { !$0.hasSuffix(".md") && !$0.hasSuffix(".tmp") })
    }

    @Test func aRememberedNoteIsFoundWithinFiveSeconds() async throws {
        let index = try folder.claude.open()
        let following = folder.follow(folder.notes, with: index)
        defer { following.cancel() }

        _ = try writer.remember("Il vicino ha le chiavi: tapiro.", titled: "Chiavi")

        #expect(try await waitUntil("tapiro", in: index, source: .secondBrain))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SessionSummaryNoteTests {
    let folder: NotesFolder
    static let session = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    init() throws {
        folder = try NotesFolder()
    }

    func writer(on day: Date = NoteWriterTests.day) -> NoteWriter {
        NoteWriter(root: folder.notes, timeZone: NoteWriterTests.rome, now: { day })
    }

    func properties(_ phase: Session.Phase = .fusa) -> SummaryProperties {
        SummaryProperties(title: "Riassunto: di Sessione", project: "bubo", branch: "bubo/riassunto", phase: phase,
                          session: Self.session, related: ["Diario"])
    }

    func text(of note: SummaryNote) throws -> String {
        try String(contentsOf: folder.notes.appending(path: note.relativePath), encoding: .utf8)
    }

    @Test func aSummaryGoesInBuboSessioniWithItsProperties() throws {
        let note = try #require(try writer().writeSessionSummary("## Fatto\n\n- uno\n", properties: properties(),
                                                                 replacing: nil))

        #expect(note.relativePath == "Bubo/Sessioni/2026-10-01 Riassunto di Sessione.md")
        #expect(note.createdOn == "2026-10-01")
        #expect(!note.isEditedByHand)
        #expect(try text(of: note) == """
            ---
            titolo: "Riassunto: di Sessione"
            progetto: "bubo"
            branch: "bubo/riassunto"
            fase: fusa
            creata: 2026-10-01
            aggiornata: 2026-10-01
            sessione: "bubo://sessione/3f2504e0-4f89-11d3-9a0c-0305e82c3301"
            correlate: ["[[Diario]]"]
            ---

            ## Fatto

            - uno

            """)
    }

    @Test func anUnchangedSummaryIsReplacedInPlaceWithItsNewFase() throws {
        let first = try #require(try writer().writeSessionSummary("primo", properties: properties(.fusa), replacing: nil))
        let later = NoteWriterTests.day.addingTimeInterval(86_400)

        let second = try #require(try writer(on: later).writeSessionSummary("secondo", properties: properties(.archiviata),
                                                                            replacing: first))

        #expect(second.relativePath == first.relativePath)
        #expect(!second.isEditedByHand)
        let text = try text(of: second)
        #expect(text.contains("fase: archiviata"))
        #expect(text.contains("creata: 2026-10-01"))
        #expect(text.contains("aggiornata: 2026-10-02"))
        #expect(text.contains("secondo"))
        #expect(!text.contains("primo"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.notes.appending(path: "Bubo/Sessioni").path)
            .count == 1)
    }

    @Test func aSummaryEditedByHandKeepsItsBytesAndGetsAnUpdateSectionAtTheEnd() throws {
        let first = try #require(try writer().writeSessionSummary("primo", properties: properties(), replacing: nil))
        let file = folder.notes.appending(path: first.relativePath)
        let edited = try text(of: first) + "Una mia nota a mano.\n"
        try edited.write(to: file, atomically: true, encoding: .utf8)

        let second = try #require(try writer().writeSessionSummary("## Fatto\n\n- altro", properties: properties(),
                                                                   replacing: first))

        #expect(second.isEditedByHand)
        let text = try text(of: second)
        #expect(text.hasPrefix(edited))
        #expect(text == edited + "\n## Aggiornamento 2026-10-01\n\n## Fatto\n\n- altro\n")
    }

    @Test func aSummaryEditedOnceIsNeverReplacedAgain() throws {
        let first = try #require(try writer().writeSessionSummary("primo", properties: properties(), replacing: nil))
        try (try text(of: first) + "a mano\n").write(to: folder.notes.appending(path: first.relativePath), atomically: true,
                                                     encoding: .utf8)

        let second = try #require(try writer().writeSessionSummary("secondo", properties: properties(), replacing: first))
        let third = try #require(try writer().writeSessionSummary("terzo", properties: properties(), replacing: second))

        let text = try text(of: third)
        #expect(third.isEditedByHand)
        #expect(text.contains("primo"))
        #expect(text.contains("a mano"))
        #expect(text.components(separatedBy: "## Aggiornamento").count == 3)
        #expect(text.hasSuffix("terzo\n"))
    }

    @Test func aDeletedSummaryIsNotWrittenAgain() throws {
        let first = try #require(try writer().writeSessionSummary("primo", properties: properties(), replacing: nil))
        try FileManager.default.removeItem(at: folder.notes.appending(path: first.relativePath))

        let second = try writer().writeSessionSummary("secondo", properties: properties(), replacing: first)

        #expect(second == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.notes.appending(path: "Bubo/Sessioni").path)
            .isEmpty)
    }

    @Test func aSummaryNeverLeavesBuboSessioni() throws {
        let elsewhere = folder.claude.folder.appending(path: "Altrove")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.notes.appending(path: "Bubo"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.notes.appending(path: "Bubo/Sessioni"),
                                                   withDestinationURL: elsewhere)

        #expect(throws: NoteWriter.Failure.outsideBubo) {
            try writer().writeSessionSummary("testo", properties: properties(), replacing: nil)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct RememberToolTests {
    let folder: NotesFolder
    let defaults: UserDefaults

    init() throws {
        folder = try NotesFolder()
        defaults = try #require(UserDefaults(suiteName: "RememberToolTests-\(UUID().uuidString)"))
    }

    @Test func withoutASecondBrainNothingIsSavedAndClaudeIsToldWhere() async {
        let model = QuestionModel(secondBrain: SecondBrain(index: nil, defaults: defaults))

        let result = await model.remember("testo", titled: "Nota")

        #expect(result.hasPrefix("Nota non salvata"))
        #expect(result.contains("Impostazioni"))
        #expect(model.savedNote == nil)
    }

    @Test func aSavedNoteIsShownInTheDomandaAndItsPathGoesToClaude() async throws {
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        let model = QuestionModel(secondBrain: secondBrain)

        let result = await model.remember("testo", titled: "Ombrello")

        let file = try #require(model.savedNote)
        #expect(file.deletingLastPathComponent().path == folder.notes.appending(path: "Bubo/Note").path)
        #expect(result == "Nota salvata nel Secondo cervello: Bubo/Note/\(file.lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aSecondBrainOutOfReachSaysSo() async throws {
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        try FileManager.default.removeItem(at: folder.notes)
        let model = QuestionModel(secondBrain: secondBrain)

        let result = await model.remember("testo", titled: "Nota")

        #expect(result.contains("non è raggiungibile"))
        #expect(model.savedNote == nil)
    }
}
