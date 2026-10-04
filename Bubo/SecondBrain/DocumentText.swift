import AppKit
import PDFKit
import Vision

/// The text of a document imported in the Secondo cervello, read on the Mac: nothing reaches the network.
nonisolated struct DocumentText: Equatable, Sendable {
    /// The kinds of document Bubo reads.
    enum Kind: String, Sendable, CaseIterable {
        case pdf = "PDF"
        case word = "Word"

        /// The kind of the file at `url`, by its extension; `nil` for any other file.
        init?(fileAt url: URL) {
            switch url.pathExtension.lowercased() {
            case "pdf": self = .pdf
            case "docx": self = .word
            default: return nil
            }
        }
    }

    /// Why a document was not read.
    enum Failure: Error, Equatable {
        /// Neither a PDF nor a `.docx`.
        case unsupported
        /// The file cannot be opened: damaged, locked by a password, or gone.
        case unreadable
        /// Not a word in it, even with the OCR.
        case empty
    }

    var kind: Kind
    /// The text, pages apart by an empty line.
    var text: String
    /// The PDF's pages; `nil` for a `.docx`, whose pages depend on how it is shown.
    var pageCount: Int?
    /// Whether some text came from the OCR, as in a scanned PDF.
    var isRecognized = false

    /// Reads the PDF or `.docx` at `url`, off the main actor; the PDF pages without text go through Vision's OCR.
    ///
    /// - Throws: `Failure` when the file is not a document Bubo reads, cannot be opened or holds no text.
    @concurrent
    static func read(_ url: URL) async throws -> DocumentText {
        let document: DocumentText
        switch Kind(fileAt: url) {
        case .pdf: document = try await readPDF(url)
        case .word: document = try readWord(url)
        case nil: throw Failure.unsupported
        }
        guard !document.text.isEmpty else { throw Failure.empty }
        return document
    }

    private static func readPDF(_ url: URL) async throws -> DocumentText {
        guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw Failure.unreadable }
        var pages: [String] = []
        var isRecognized = false
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { continue }
            var text = trimmed(page.string ?? "")
            if text.isEmpty {
                text = try await recognizedText(on: page)
                isRecognized = isRecognized || !text.isEmpty
            }
            if !text.isEmpty { pages.append(text) }
        }
        return DocumentText(kind: .pdf, text: pages.joined(separator: "\n\n"), pageCount: pdf.pageCount,
                            isRecognized: isRecognized)
    }

    private static func readWord(_ url: URL) throws -> DocumentText {
        guard let text = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                                 documentAttributes: nil) else {
            throw Failure.unreadable
        }
        return DocumentText(kind: .word, text: trimmed(text.string))
    }

    /// The text Vision reads on `page`, drawn at twice its size; empty when it finds none.
    private static func recognizedText(on page: PDFPage) async throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        var request = RecognizeTextRequest()
        request.automaticallyDetectsLanguage = true
        let lines = try await request.perform(on: picture).compactMap { $0.topCandidates(1).first?.string }
        return trimmed(lines.joined(separator: "\n"))
    }

    /// `text` without spaces at its ends and with Windows and old Mac line ends made `\n`.
    private static func trimmed(_ text: String) -> String {
        text.replacing("\r\n", with: "\n").replacing("\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
