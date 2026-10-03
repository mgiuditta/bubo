import AppKit
import Foundation
import PDFKit
import Testing
@testable import Bubo

/// A summary engine that answers `answer`, and says whether it needs the network.
private struct StubSummaryEngine: SummaryEngine {
    var answer: String
    var needsNetwork = false

    func summary(of input: SummaryInput) async throws -> SessionSummary { throw SummaryEngineError.unavailable }

    func shortText(for prompt: String, following instructions: String, session: UUID) async throws -> String {
        answer
    }
}

@Suite(.timeLimit(.minutes(1)))
struct DocumentImportTests {
    let folder: NotesFolder
    let defaults: UserDefaults

    init() throws {
        folder = try NotesFolder()
        defaults = try #require(UserDefaults(suiteName: "DocumentImportTests-\(UUID().uuidString)"))
    }

    /// A file named `name` outside the Secondo cervello.
    func file(named name: String) -> URL {
        folder.claude.folder.appending(path: name)
    }

    /// A `.docx` holding `text`, written as Word writes it.
    func makeWordDocument(_ text: String, named name: String = "Verbale.docx") throws -> URL {
        let url = file(named: name)
        let data = try NSAttributedString(string: text).data(
            from: NSRange(location: 0, length: text.utf16.count),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: url)
        return url
    }

    /// A one-page PDF with `text` as text, as a word processor exports it.
    func makeTextPDF(_ text: String) throws -> URL {
        let url = file(named: "Contratto.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            .draw(at: CGPoint(x: 50, y: 700))
        NSGraphicsContext.current = nil
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// A one-page PDF with `text` only as a picture, as a scanner makes it.
    func makeScannedPDF(_ text: String) throws -> URL {
        let url = file(named: "Scansione.pdf")
        let image = NSImage(size: CGSize(width: 1200, height: 400), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 64),
                                                          .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: 40, y: 160))
            return true
        }
        let page = try #require(PDFPage(image: image))
        let document = PDFDocument()
        document.insert(page, at: 0)
        #expect(document.write(to: url))
        return url
    }

    func makeImporter(engines: [any SummaryEngine] = []) -> DocumentImporter {
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        return DocumentImporter(secondBrain: secondBrain, engines: engines)
    }

    @Test func aPDFWithTextIsReadWithItsPages() async throws {
        let document = try await DocumentText.read(try makeTextPDF("Clausola di riservatezza"))

        #expect(document.kind == .pdf)
        #expect(document.text.contains("Clausola di riservatezza"))
        #expect(document.pageCount == 1)
        #expect(!document.isRecognized)
    }

    @Test func aScannedPDFIsReadWithTheOCR() async throws {
        let document = try await DocumentText.read(try makeScannedPDF("Fattura numero 42"))

        #expect(document.text.localizedStandardContains("Fattura"))
        #expect(document.isRecognized)
    }

    @Test func aWordDocumentIsRead() async throws {
        let document = try await DocumentText.read(try makeWordDocument("Ordine del giorno: bilancio"))

        #expect(document.kind == .word)
        #expect(document.text == "Ordine del giorno: bilancio")
        #expect(document.pageCount == nil)
    }

    @Test func anotherFileIsRefused() async throws {
        let url = file(named: "note.txt")
        try "testo".write(to: url, atomically: true, encoding: .utf8)

        await #expect(throws: DocumentText.Failure.unsupported) { try await DocumentText.read(url) }
    }

    @Test func theNoteHasPropertiesForObsidianTheSummaryAndTheText() {
        let note = DocumentNote(title: "Contratto", source: "Contratto.pdf",
                                document: DocumentText(kind: .pdf, text: "Testo.", pageCount: 3, isRecognized: true),
                                fingerprint: "abc", summary: "Un contratto.")

        #expect(note.markdown(importedOn: "2026-10-03") == """
            ---
            titolo: "Contratto"
            fonte: "Contratto.pdf"
            tipo: PDF
            importata: 2026-10-03
            pagine: 3
            ocr: true
            impronta: "abc"
            ---

            ## Riassunto

            Un contratto.

            ## Testo

            Testo.

            """)
        #expect(DocumentNote.note(note.markdown(importedOn: "2026-10-03"), isOfFileWithFingerprint: "abc"))
        #expect(!DocumentNote.note(note.markdown(importedOn: "2026-10-03"), isOfFileWithFingerprint: "ab"))
    }

    @Test func anImportedDocumentGoesInBuboDocumentiWithTheOnDeviceSummary() async throws {
        let importer = makeImporter(engines: [StubSummaryEngine(answer: "In rete.", needsNetwork: true),
                                              StubSummaryEngine(answer: "Sul Mac.")])

        let outcome = try await importer.importDocument(at: try makeWordDocument("Bilancio approvato"))

        guard case .imported(let note) = outcome else {
            Issue.record("Not imported: \(outcome)")
            return
        }
        #expect(note.path == folder.notes.appending(path: "Bubo/Documenti/Verbale.md").path)
        let text = try String(contentsOf: note, encoding: .utf8)
        #expect(text.contains("## Riassunto\n\nSul Mac."))
        #expect(text.contains("Bilancio approvato"))
        #expect(text.contains("fonte: \"Verbale.docx\""))
    }

    @Test func theSameFileIsNotImportedTwiceEvenUnderAnotherName() async throws {
        let importer = makeImporter()
        let original = try makeWordDocument("Bilancio approvato")
        let copy = file(named: "Copia.docx")
        try FileManager.default.copyItem(at: original, to: copy)

        let first = try await importer.importDocument(at: original)
        let second = try await importer.importDocument(at: copy)

        guard case .imported(let note) = first, case .alreadyImported(let existing) = second else {
            Issue.record("Imported \(first), then \(second)")
            return
        }
        #expect(existing.resolvingSymlinksInPath() == note.resolvingSymlinksInPath())
        let documents = try FileManager.default.contentsOfDirectory(atPath: folder.notes.appending(path: "Bubo/Documenti").path)
        #expect(documents == ["Verbale.md"])
    }

    @Test func withoutASecondBrainNothingIsImported() async throws {
        let importer = DocumentImporter(secondBrain: SecondBrain(index: nil, defaults: defaults), engines: [])

        #expect(!importer.canImport)
        await #expect(throws: NoteWriter.Failure.unreachable) {
            try await importer.importDocument(at: try makeWordDocument("Testo"))
        }
    }

    @Test func theIndiceReadsTheDocuments() {
        #expect(!SecondBrainNotes.skips("Bubo/Documenti/Contratto.md"))
    }
}
