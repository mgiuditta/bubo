import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct MeetingNoteTests {
    let folder: NotesFolder
    /// 1 October 2026, 00:30 in Rome: still 30 September in UTC, so the date must be Rome's.
    nonisolated static let start = Date(timeIntervalSince1970: 1_790_807_400)
    static let rome = TimeZone(identifier: "Europe/Rome")!

    init() throws {
        folder = try NotesFolder()
    }

    var note: MeetingNote {
        MeetingNote(title: "Budget \"Q4\": decisione", start: Self.start, duration: .seconds(301), app: "Zoom",
                    summary: MeetingSummary(summary: ["Budget del Q4"], decisions: ["Si taglia il 10%"],
                                            actions: ["Anna manda il piano"]),
                    transcript: [MeetingLine(speaker: .me, start: .seconds(3), text: "Partiamo dal budget."),
                                 MeetingLine(speaker: .others, start: .seconds(83), text: "Taglierei il 10%.")])
    }

    @Test func theNoteGoesInBuboRiunioniWithValidPropertiesTheSummaryAndTheTranscript() throws {
        let written = try NoteWriter(root: folder.notes, timeZone: Self.rome).writeMeeting(note)

        #expect(written.file.path == folder.notes.appending(path: "Bubo/Riunioni/2026-10-01 Budget Q4 decisione.md").path)
        #expect(try String(contentsOf: written.file, encoding: .utf8) == """
            ---
            titolo: "Budget \\"Q4\\": decisione"
            data: 2026-10-01
            ora: "00:30"
            durata: "6 min"
            app: "Zoom"
            partecipanti: []
            fonte: Riunione
            ---

            ## Riassunto

            - Budget del Q4

            ## Decisioni

            - Si taglia il 10%

            ## Azioni

            - Anna manda il piano

            ## Trascrizione

            **[0:00:03] Io:** Partiamo dal budget.

            **[0:01:23] Altri:** Taglierei il 10%.

            """)
    }

    @Test func withoutSummaryNorWordsTheNoteSaysSo() {
        var note = note
        note.summary = nil
        note.transcript = []
        note.app = nil

        let markdown = note.markdown(in: Self.rome)

        #expect(markdown.contains("app: \"\"\n"))
        #expect(markdown.contains("Non scritto: nessun modello era disponibile."))
        #expect(markdown.hasSuffix("## Trascrizione\n\nNessuna parola riconosciuta.\n"))
    }

    @Test func theTracksMergeInTheOrderTheyWereSaidWithoutEmptyLines() {
        let mine = [MeetingLine(speaker: .me, start: .seconds(10), text: "dopo"),
                    MeetingLine(speaker: .me, start: .seconds(1), text: "insieme"),
                    MeetingLine(speaker: .me, start: .seconds(4), text: "  ")]
        let others = [MeetingLine(speaker: .others, start: .seconds(1), text: "anche"),
                      MeetingLine(speaker: .others, start: .seconds(5), text: "in mezzo")]

        #expect(MeetingLine.merged(mine, others).map(\.text) == ["insieme", "anche", "in mezzo", "dopo"])
    }

    @Test func theSummaryIsReadFromTheModelsSectionsAndLosesItsSecrets() {
        let answer = """
            Ecco il riassunto.
            ## Riassunto
            - Si parla del rilascio
            ## Decisioni
            1. Rilascio venerdì
            ## Azioni
            * Marco passa la chiave sk-ant-abcdefghijklmnopqrstuvwxyz
            ## Altro
            - ignorato
            """

        let summary = MeetingSummary(markdown: answer).redacted(by: SecretFilter())

        #expect(summary.summary == ["Si parla del rilascio"])
        #expect(summary.decisions == ["Rilascio venerdì"])
        #expect(summary.actions == ["Marco passa la chiave \(SecretFilter.replacement)"])
    }

    @Test(arguments: [("us.zoom.xos", "us.zoom.xos", true), ("com.google.Chrome.helper", "com.google.Chrome", true),
                      ("com.google.ChromeCanary", "com.google.Chrome", false), ("com.apple.Safari", "us.zoom.xos", false)])
    func helpersBelongToTheirApp(process: String, app: String, belongs: Bool) {
        #expect(AudioProcesses.belongs(process, to: app) == belongs)
    }

    @Test func callAppsComeFirstThenByName() {
        let apps = [MeetingApp(name: "Note", bundleID: "com.apple.Notes"),
                    MeetingApp(name: "Chrome", bundleID: "com.google.Chrome"),
                    MeetingApp(name: "Anteprima", bundleID: "com.apple.Preview"),
                    MeetingApp(name: "zoom.us", bundleID: "us.zoom.xos")]

        #expect(MeetingApp.ordered(apps).map(\.name) == ["zoom.us", "Chrome", "Anteprima", "Note"])
    }

    @Test func audioOlderThanThirtyDaysIsDeletedTheRestStays() throws {
        let store = MeetingAudioStore(folder: folder.claude.folder.appending(path: "Riunioni"))
        let old = try store.makeRecordingFolder()
        let recent = try store.makeRecordingFolder()
        try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(-31 * 24 * 3600)],
                                              ofItemAtPath: old.path)

        store.removeExpired()

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }

    @Test func theRetentionIsThirtyDaysUntilChosen() throws {
        let defaults = try #require(UserDefaults(suiteName: "MeetingNoteTests-\(UUID().uuidString)"))
        #expect(MeetingAudioRetention.saved(in: defaults) == .thirtyDays)
        defaults.set(MeetingAudioRetention.afterTranscription.rawValue, forKey: MeetingAudioRetention.defaultsKey)
        #expect(MeetingAudioRetention.saved(in: defaults) == .afterTranscription)
    }
}

/// A model that answers each piece with an action quoting the piece's last line, keeping every prompt it read.
@MainActor
final class FakeMeetingEngine: SummaryEngine {
    let needsNetwork = false
    private(set) var prompts: [(prompt: String, instructions: String)] = []

    func summary(of input: SummaryInput) async throws -> SessionSummary { throw SummaryEngineError.unavailable }

    func shortText(for prompt: String, following instructions: String, session: UUID) async throws -> String {
        prompts.append((prompt, instructions))
        let last = prompt.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        return "## Riassunto\n## Decisioni\n## Azioni\n- \(last.trimmingPrefix("- "))\n"
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingRecorderTests {
    @Test func aSixtyMinuteRiunioneIsSummarizedInPiecesUpToItsLastPart() async throws {
        // One line every 10 seconds for an hour: about 40,000 characters.
        let transcript = (0..<360).map { index in
            MeetingLine(speaker: index.isMultiple(of: 2) ? .me : .others, start: .seconds(index * 10),
                        text: "Frase numero \(index) della Riunione, con qualche parola in più per farla lunga.")
        }
        let text = transcript.map(\.markdown).joined(separator: "\n")
        let engine = FakeMeetingEngine()

        let answer = try await MeetingRecorder.summaryText(of: text, by: engine)

        #expect(text.count > 30_000)
        #expect(engine.prompts.allSatisfy { $0.prompt.count <= MeetingRecorder.pieceLimit })
        #expect(engine.prompts.contains { $0.prompt.contains("Frase numero 359 ") })
        #expect(engine.prompts.last?.instructions == MeetingSummary.joiningInstructions)
        #expect(answer.contains("Frase numero 359 "))
    }

    @Test func aShortRiunioneIsSummarizedAtOnce() async throws {
        let engine = FakeMeetingEngine()

        _ = try await MeetingRecorder.summaryText(of: "**[0:00:01] Io:** Ciao.", by: engine)

        #expect(engine.prompts.count == 1)
        #expect(engine.prompts.first?.instructions == MeetingSummary.instructions)
    }

    @Test func piecesKeepEveryCharacterAndStayWithinTheLimit() {
        let text = ["corta", String(repeating: "x", count: 25), "altra riga"].joined(separator: "\n")

        let pieces = MeetingSummary.pieces(of: text, limit: 10)

        #expect(pieces.allSatisfy { $0.count <= 10 })
        #expect(pieces.joined().filter { $0 != "\n" } == text.filter { $0 != "\n" })
    }

    @Test func retryWritesTheNoteFromTheKeptAudioAfterAFailure() async throws {
        let folder = try NotesFolder()
        let defaults = try #require(UserDefaults(suiteName: "MeetingRecorderTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        var failsNext = true
        let recorder = MeetingRecorder(secondBrain: secondBrain, engines: [FakeMeetingEngine()], store: nil,
                                       defaults: defaults) { _, speaker throws(MeetingFailure) in
            if failsNext {
                failsNext = false
                throw .transcriptionFailed
            }
            return [MeetingLine(speaker: speaker, start: .seconds(1), text: "Partiamo.")]
        }
        let recording = MeetingRecorder.Recording(title: "Prova", app: nil, start: .now,
                                                  folder: folder.claude.folder)

        await recorder.process(recording, lasting: .seconds(60))
        #expect(recorder.phase == .failed(.transcriptionFailed))
        #expect(recorder.canRetry)

        await recorder.retry()

        guard case let .saved(file) = recorder.phase else {
            Issue.record("Not saved: \(recorder.phase)")
            return
        }
        #expect(try String(contentsOf: file, encoding: .utf8).contains("Partiamo."))
        #expect(!recorder.canRetry)
    }
}
