import Foundation
import PDFKit
import UniformTypeIdentifiers

/// A text, file, folder or image that comes with a Richiesta (spec 09, Allegati e fornitori).
///
/// Claude reads a file, a folder or an image from its path; a model on the Mac reads only its text, and only when
/// `AttachmentPolicy` lets it.
nonisolated struct Allegato: Hashable, Sendable {
    /// What an Allegato is, which tells who may read it.
    enum Kind: Hashable, Sendable {
        /// Text or a web address, with no file behind it.
        case text
        /// A file that is not an image.
        case file
        /// A folder, which goes only as a path.
        case folder
        /// An image, a screenshot among them, which goes only as a path.
        case image
    }

    /// The name shown in its chip, without its path: all a classifier may see of it.
    let name: String
    /// What it is.
    let kind: Kind
    /// The content a model on the Mac or another provider reads: a text file's, or the text extracted from a PDF; `nil`
    /// for a folder, an image, and a file that is not text or is over ``readableSize``.
    let text: String?
    /// Where `claude` reads it; `nil` for text with no file behind it.
    let path: URL?

    /// The largest file whose text is read at once: far over what a model on the Mac takes, and read in a blink.
    static let readableSize = 256 * 1024

    /// Creates an Allegato of `text`, with no file behind it, shown as `name`.
    init(name: String, text: String) {
        self.name = name
        kind = .text
        self.text = text
        path = nil
    }

    /// The largest PDF whose text is extracted at once.
    static let readablePDFSize = 10 * 1024 * 1024

    /// Creates the Allegato of the file or folder at `url`, reading its text now when it is a text file up to
    /// ``readableSize``, or a PDF up to ``readablePDFSize`` with up to ``readableSize`` characters of text.
    init(fileAt url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey, .fileSizeKey, .isPackageKey])
        name = url.lastPathComponent
        path = url
        if values?.isDirectory == true, values?.isPackage != true {
            kind = .folder
            text = nil
        } else if values?.contentType?.conforms(to: .image) == true {
            kind = .image
            text = nil
        } else {
            kind = .file
            let size = values?.fileSize ?? .max
            if values?.contentType?.conforms(to: .pdf) == true {
                let extracted = size <= Self.readablePDFSize ? PDFDocument(url: url)?.string : nil
                text = extracted.flatMap { $0.count <= Self.readableSize ? $0 : nil }
            } else {
                let isText = values?.contentType?.conforms(to: .text) == true
                text = isText && size <= Self.readableSize ? (try? String(contentsOf: url, encoding: .utf8)) : nil
            }
        }
    }

    /// Creates the Allegato of a dragged `address`: a web page `claude` may open, as text.
    init(address: URL) {
        self.init(name: address.host() ?? address.absoluteString, text: address.absoluteString)
    }

    /// Creates the Allegato of a dragged `text`, named after its first words.
    init(draggedText text: String) {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let name = trimmed.count > Self.nameLength ? trimmed.prefix(Self.nameLength) + "…" : trimmed
        self.init(name: name, text: text)
    }

    /// The characters of a dragged text that name it.
    private static let nameLength = 32
}
