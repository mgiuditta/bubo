import Foundation
import os

/// The visore: one file in read-only, at the line a terminal link or another view pointed to (spec 15).
@Observable
final class CodeViewerStore {
    /// What the visore shows.
    nonisolated enum Content: Equatable, Sendable {
        case loading
        /// The file's lines.
        case lines([CodeLine])
        /// Why the file does not show; "Apri nell'editor" still does.
        case unreadable(String)
    }

    /// The file and line shown.
    private(set) var location: SourceLocation?
    /// The Sessione's folder the file belongs to, the editor's window when the file is inside it.
    private(set) var folder: URL?
    private(set) var content = Content.loading

    /// The largest file the visore reads; larger ones open only in the editor.
    nonisolated static let maximumSize = 2 * 1_024 * 1_024

    @ObservationIgnored private var window: CodeViewerWindow?
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// The file's path, from the Sessione's folder when it is inside it.
    var path: String {
        guard let file = location?.file.path else { return "" }
        if let folder = folder?.standardizedFileURL.path, file.hasPrefix(folder + "/") {
            return String(file.dropFirst(folder.count + 1))
        }
        return NSString(string: file).abbreviatingWithTildeInPath
    }

    /// Shows `location` in the visore's window, reading the file again.
    func show(_ location: SourceLocation, in folder: URL?) {
        self.location = location
        self.folder = folder
        content = .loading
        if window == nil { window = CodeViewerWindow(store: self) }
        window?.show()
        loading?.cancel()
        loading = Task {
            let content = await Self.read(location.file)
            guard !Task.isCancelled else { return }
            self.content = content
        }
    }

    /// The highlighted lines of `file`, or why it does not show.
    @concurrent
    static func read(_ file: URL) async -> Content {
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumSize else {
                return .unreadable(String(localized: "Il file è troppo grande per il visore."))
            }
            let data = try Data(contentsOf: file)
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                return .unreadable(String(localized: "Non è un file di testo."))
            }
            return .lines(lines(of: text, fileExtension: file.pathExtension))
        } catch {
            Logger.editor.error("Visore: file not read: \(String(describing: error), privacy: .private)")
            return .unreadable(String(localized: "Non riesco a leggere il file."))
        }
    }

    /// The lines of `text`, each with its keywords, strings, numbers and comments.
    nonisolated static func lines(of text: String, fileExtension: String) -> [CodeLine] {
        // `\r\n` is one Character. Only the line ends compilers count: a form feed is not one.
        var lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
            .map(String.init)
        // A file ending in a newline has no empty line after it.
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        let spans = SyntaxHighlighter.spans(of: lines, fileExtension: fileExtension)
        return zip(lines, spans).map { CodeLine(text: $0, spans: $1) }
    }
}
