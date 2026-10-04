import Foundation
import Testing
@testable import Bubo

/// #574: the user names the speakers; the note keeps its file name, so the links to it stay valid.
@Suite(.timeLimit(.minutes(1)))
struct MeetingSpeakersTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    /// A Riunione written as Bubo writes it, with two speakers and a reply of «Parlante 12» to test the numbers.
    var note: MeetingNote {
        MeetingNote(title: "Budget", start: MeetingNoteTests.start, duration: .seconds(120), app: "Zoom",
                    summary: MeetingSummary(summary: ["Parlante 1 propone il taglio"], decisions: [], actions: []),
                    transcript: [MeetingLine(speaker: .me, start: .seconds(3), text: "Partiamo."),
                                 MeetingLine(speaker: .participant(1), start: .seconds(83), text: "Taglierei il 10%."),
                                 MeetingLine(speaker: .participant(2), start: .seconds(90), text: "D'accordo."),
                                 MeetingLine(speaker: .participant(1), start: .seconds(95), text: "Bene.")])
    }

    func written() throws -> URL {
        try NoteWriter(root: folder.notes, timeZone: MeetingNoteTests.rome).writeMeeting(note).file
    }

    @Test func theSpeakersToNameAreTheNumberedOnesInTheOrderTheySpeak() throws {
        let text = try String(contentsOf: written(), encoding: .utf8)

        #expect(MeetingSpeakers.named(in: text) == ["Parlante 1", "Parlante 2"])
    }

    @Test func renamingASpeakerRewritesTheTranscriptTheSummaryAndTheParticipantsInTheSameFile() throws {
        let file = try written()

        try MeetingSpeakers.rename("Parlante 1", to: "Giulia", inNoteAt: file)

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).count == 1)
        #expect(text.contains(#"partecipanti: ["[[Giulia]]"]"#))
        #expect(text.contains("**[0:01:23] [[Giulia]]:** Taglierei il 10%."))
        #expect(text.contains("**[0:01:35] [[Giulia]]:** Bene."))
        #expect(text.contains("**[0:01:30] Parlante 2:** D'accordo."))
        #expect(text.contains("- [[Giulia]] propone il taglio"))
        #expect(text.contains("**[0:00:03] Io:** Partiamo."))
        #expect(MeetingSpeakers.named(in: text) == ["[[Giulia]]", "Parlante 2"])
    }

    @Test func renamingTheSameSpeakerTwiceDoesNotDuplicateTheParticipant() throws {
        var text = try String(contentsOf: written(), encoding: .utf8)

        text = MeetingSpeakers.renaming("Parlante 1", to: "Giulia", in: text)
        text = MeetingSpeakers.renaming("[[Giulia]]", to: "Giulia", in: text)
        #expect(text.contains(#"partecipanti: ["[[Giulia]]"]"#))

        text = MeetingSpeakers.renaming("[[Giulia]]", to: "Giulia Rossi", in: text)
        #expect(text.contains(#"partecipanti: ["[[Giulia Rossi]]"]"#))
        #expect(!text.contains("[[Giulia]]"))
    }

    @Test func twoSpeakersWithTheSameNameAreOneParticipant() throws {
        var text = try String(contentsOf: written(), encoding: .utf8)

        text = MeetingSpeakers.renaming("Parlante 1", to: "Giulia", in: text)
        text = MeetingSpeakers.renaming("Parlante 2", to: "Marco", in: text)
        text = MeetingSpeakers.renaming("[[Marco]]", to: "Giulia", in: text)

        #expect(text.contains(#"partecipanti: ["[[Giulia]]"]"#))
        #expect(MeetingSpeakers.named(in: text) == ["[[Giulia]]"])
    }

    @Test func aDoubleDigitSpeakerIsNotTakenForTheFirst() {
        let text = "---\npartecipanti: []\n---\n\n**[0:00:01] Parlante 1:** Sì.\n\n**[0:00:02] Parlante 12:** No.\n"

        let renamed = MeetingSpeakers.renaming("Parlante 1", to: "Anna", in: text)

        #expect(renamed.contains("**[0:00:02] Parlante 12:** No."))
        #expect(renamed.contains("**[0:00:01] [[Anna]]:** Sì."))
    }

    @Test(arguments: ["", "  ", "[[]]"])
    func anEmptyNameLeavesTheNoteAsItIs(name: String) throws {
        let text = try String(contentsOf: written(), encoding: .utf8)

        #expect(MeetingSpeakers.renaming("Parlante 1", to: name, in: text) == text)
    }

    @Test func meAndTheOthersCannotBeRenamed() throws {
        let text = try String(contentsOf: written(), encoding: .utf8)

        #expect(MeetingSpeakers.renaming("Io", to: "Matteo", in: text) == text)
    }

    @Test func theCharactersThatBreakALinkAreDropped() throws {
        let text = try String(contentsOf: written(), encoding: .utf8)

        let renamed = MeetingSpeakers.renaming("Parlante 1", to: "Giu|lia #1\n", in: text)

        #expect(renamed.contains(#"partecipanti: ["[[Giulia 1]]"]"#))
    }
}
