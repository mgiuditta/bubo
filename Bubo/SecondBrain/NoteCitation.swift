import Foundation

/// A note of the Secondo cervello cited in an answer as a wikilink: `[[Bubo/Riunioni/2026-10-03 Standup#12:40]]`.
///
/// The `cerca` tool gives each note its citation, the note's path relative to the Secondo cervello without `.md`,
/// so a citation finds its file without a search; a citation by the note's name alone, as Obsidian writes it, is
/// looked up by name.
nonisolated struct NoteCitation: Equatable, Sendable {
    /// The cited note: its path relative to the Secondo cervello, or only its name, without `.md`.
    var note: String
    /// Where in the note: a heading or, for a Riunione, the minute; `nil` for the whole note.
    var anchor: String?

    /// The scheme of the links that carry a citation inside an answer.
    static let scheme = "bubo-nota"

    /// Creates the citation of `note`, at `anchor` if any.
    init(note: String, anchor: String? = nil) {
        self.note = note
        self.anchor = anchor
    }

    /// Creates the citation inside a wikilink, `inner` being what stands between `[[` and `]]`; `nil` when empty.
    ///
    /// An alias after `|` is dropped: the answer shows the note's name.
    init?(wikilink inner: some StringProtocol) {
        let target = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let note = parts[0].trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty else { return nil }
        let anchor = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        self.init(note: note, anchor: anchor.isEmpty ? nil : anchor)
    }

    /// Creates the citation a link made by ``link`` carries; `nil` for any other link.
    init?(link: URL) {
        guard link.scheme == Self.scheme,
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let note = items.first(where: { $0.name == "nota" })?.value else { return nil }
        self.init(note: note, anchor: items.first { $0.name == "punto" }?.value)
    }

    /// The citation of the note at `path`, inside the Secondo cervello at `folder`; `nil` for a file outside it.
    init?(path: String, inFolder folder: String) {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
        let relativePath = String(path.dropFirst(prefix.count))
        self.init(note: relativePath.lowercased().hasSuffix(".md") ? String(relativePath.dropLast(3)) : relativePath)
    }

    /// The wikilink that cites the note, as the model is asked to write it.
    var wikilink: String { "[[\(note)]]" }

    /// The link that carries the citation inside an answer.
    var link: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "apri"
        components.queryItems = [URLQueryItem(name: "nota", value: note)] + (anchor.map { [URLQueryItem(name: "punto", value: $0)] } ?? [])
        // Built from a fixed scheme and host and encoded query items: always a valid URL.
        return components.url ?? URL(filePath: note)
    }

    /// The text the answer shows for the citation: the note's name, and where in it.
    var title: String {
        let name = note.split(separator: "/").last.map(String.init) ?? note
        return anchor.map { "\(name) · \($0)" } ?? name
    }

    /// The file of the cited note inside the Secondo cervello at `folder`; `nil` when there is none.
    ///
    /// A path is tried first; otherwise the note with that name nearest to the top of the folder, as Obsidian does.
    func file(inFolder folder: URL) -> URL? {
        let root = folder.standardizedFileURL.path + "/"
        let candidates = [note + ".md", note].map { folder.appending(path: $0) }
        // `..` in a citation never leaves the Secondo cervello.
        if let direct = candidates.first(where: { isFile($0) && $0.standardizedFileURL.path.hasPrefix(root) }) {
            return direct
        }
        guard !note.contains("/"),
              let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                   options: [.skipsHiddenFiles]) else { return nil }
        let name = note.lowercased()
        return entries.compactMap { $0 as? URL }
            .filter { file in
                let fileName = file.lastPathComponent.lowercased()
                return fileName == name + ".md" || fileName == name
            }
            .min { $0.pathComponents.count < $1.pathComponents.count }
    }

    /// Whether `url` is a regular file.
    private func isFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// Returns `answer` with every wikilink turned into a link that carries its citation and shows ``title``.
    ///
    /// The rest of the text is left exactly as written.
    static func linking(_ answer: String) -> AttributedString {
        pieces(of: answer).reduce(into: AttributedString()) { linked, piece in
            switch piece {
            case let .text(text):
                linked += AttributedString(text)
            case let .citation(citation):
                var cited = AttributedString(citation.title)
                cited.link = citation.link
                linked += cited
            }
        }
    }

    /// Returns `markdown` with every wikilink turned into a Markdown link that carries its citation and shows
    /// ``title``, escaped so that it reads as written.
    ///
    /// The rest of the text is left exactly as written.
    static func markdownLinking(_ markdown: String) -> String {
        pieces(of: markdown).reduce(into: "") { linked, piece in
            switch piece {
            case let .text(text):
                linked += text
            case let .citation(citation):
                // Every ASCII punctuation mark escaped: a `_` or `*` in a note's name is not emphasis.
                let title = citation.title.map { $0.isASCII && ($0.isPunctuation || $0.isSymbol) ? "\\\($0)" : "\($0)" }
                linked += "[\(title.joined())](<\(citation.link.absoluteString)>)"
            }
        }
    }

    /// A piece of an answer: text as written, or a wikilink's citation.
    private enum Piece {
        case text(Substring)
        case citation(NoteCitation)
    }

    /// The pieces of `answer` in order: the text between wikilinks and each wikilink's citation.
    private static func pieces(of answer: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = answer[...]
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            let inner = rest[open.upperBound..<close.lowerBound]
            // Not a wikilink: the `[[` stays as written and the search goes on after it.
            guard !inner.contains("\n"), !inner.contains("[["), let citation = NoteCitation(wikilink: inner) else {
                pieces.append(.text(rest[..<open.upperBound]))
                rest = rest[open.upperBound...]
                continue
            }
            pieces.append(.text(rest[..<open.lowerBound]))
            pieces.append(.citation(citation))
            rest = rest[close.upperBound...]
        }
        pieces.append(.text(rest))
        return pieces
    }
}
