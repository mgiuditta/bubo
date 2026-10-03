import AppKit
import Observation
import UniformTypeIdentifiers
import os

/// Imports PDF and `.docx` files in the Secondo cervello, as notes of `Bubo/Documenti/` the Indice finds.
///
/// Everything happens on the Mac: the text with PDFKit, the OCR with Vision, the summary only with on-device models.
@Observable
final class DocumentImporter {
    /// What importing one file did.
    enum Outcome: Equatable {
        /// A new note, at this file.
        case imported(URL)
        /// The same file was imported before, as the note at this file: nothing written.
        case alreadyImported(URL)
    }

    /// Creates the importer writing in `secondBrain`, summarizing with the first of `engines` that answers; the
    /// engines that need the network are never used.
    init(secondBrain: SecondBrain, engines: [any SummaryEngine]) {
        self.secondBrain = secondBrain
        self.engines = engines.filter { !$0.needsNetwork }
    }

    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private let engines: [any SummaryEngine]

    /// Whether files are being imported now.
    private(set) var isImporting = false

    /// Whether «Importa nel Secondo cervello…» can start: a folder chosen and no import running.
    var canImport: Bool { secondBrain.location != nil && !isImporting }

    /// The files the importer reads.
    static let contentTypes: [UTType] = [.pdf, UTType("org.openxmlformats.wordprocessingml.document")].compactMap(\.self)

    /// Imports the file at `url` in `Bubo/Documenti/`, unless the same file already is there.
    ///
    /// - Throws: `NoteWriter.Failure.unreachable` also when no folder is chosen; `DocumentText.Failure` when the file
    ///   cannot be read; a file system error when the note cannot be written.
    func importDocument(at url: URL) async throws -> Outcome {
        guard let location = secondBrain.location else { throw NoteWriter.Failure.unreachable }
        let writer = NoteWriter(root: location.url)
        let fingerprint = try await Self.fingerprint(of: url)
        if let existing = await Self.documentNote(withFingerprint: fingerprint, with: writer) {
            return .alreadyImported(existing)
        }
        let document = try await DocumentText.read(url)
        let note = DocumentNote(title: url.deletingPathExtension().lastPathComponent, source: url.lastPathComponent,
                                document: document, fingerprint: fingerprint, summary: await summary(of: document))
        let written = try await Self.write(note, with: writer)
        Logger.index.notice("Document imported in the Secondo cervello")
        return .imported(written.file)
    }

    /// Asks for PDF and `.docx` files, imports them, then tells what was imported.
    func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.contentTypes
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Scegli i PDF e i documenti Word da importare.")
        panel.prompt = String(localized: "Importa")
        NSApp.activate()
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        isImporting = true
        Task {
            var imported: [String] = []
            var already: [String] = []
            var failed: [String] = []
            for url in urls {
                do {
                    switch try await importDocument(at: url) {
                    case .imported: imported.append(url.lastPathComponent)
                    case .alreadyImported: already.append(url.lastPathComponent)
                    }
                } catch {
                    Logger.index.error("Could not import a document: \(error)")
                    failed.append(url.lastPathComponent)
                }
            }
            isImporting = false
            Self.report(imported: imported, alreadyImported: already, failed: failed)
        }
    }

    /// The summary of `document` from the first engine that answers; `nil` when none does.
    private func summary(of document: DocumentText) async -> String? {
        for engine in engines {
            do {
                return try await engine.shortText(for: document.text, following: DocumentNote.instructions, session: UUID())
            } catch {
                Logger.index.notice("No summary for an imported document: \(error)")
            }
        }
        return nil
    }

    /// Tells what an import did, by the files' names.
    private static func report(imported: [String], alreadyImported: [String], failed: [String]) {
        let alert = NSAlert()
        alert.messageText = switch imported.count {
        case 0: String(localized: "Nessun documento importato")
        case 1: String(localized: "Documento importato")
        default: String(localized: "Documenti importati")
        }
        var lines: [String] = []
        if !imported.isEmpty { lines.append(String(localized: "Importati: \(imported.formatted()).")) }
        if !alreadyImported.isEmpty {
            lines.append(String(localized: "Già nel Secondo cervello: \(alreadyImported.formatted())."))
        }
        if failed.count == 1 {
            lines.append(String(localized: "Impossibile leggere: \(failed.formatted()). Il file potrebbe essere danneggiato o protetto da password."))
        } else if failed.count > 1 {
            lines.append(String(localized: "Impossibile leggere: \(failed.formatted()). I file potrebbero essere danneggiati o protetti da password."))
        }
        alert.informativeText = lines.joined(separator: "\n")
        NSApp.activate()
        alert.runModal()
    }

    @concurrent
    private static func fingerprint(of url: URL) async throws -> String {
        NoteWriter.hash(of: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    @concurrent
    private static func documentNote(withFingerprint fingerprint: String, with writer: NoteWriter) async -> URL? {
        writer.documentNote(withFingerprint: fingerprint)
    }

    @concurrent
    private static func write(_ note: DocumentNote, with writer: NoteWriter) async throws -> NoteWriter.WrittenNote {
        try writer.writeDocument(note)
    }
}
