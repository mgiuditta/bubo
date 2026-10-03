import Foundation

/// A link from one note of the Secondo cervello to another, as Obsidian writes it: a wikilink or a Markdown link to a
/// relative path.
nonisolated struct NoteLink: Hashable, Codable, Sendable {
    /// How the link names its note.
    enum Kind: Hashable, Codable, Sendable {
        /// `[[Nota]]`, `[[Nota|alias]]`, `[[cartella/Nota#Titolo]]` or `![[Nota]]`: a name or a path from the top.
        case wikilink
        /// `[testo](../cartella/Nota%20uno.md)`: a path from the folder of the note that links, already decoded.
        case relative
    }

    /// The linked note, without alias and section.
    var target: String
    var kind: Kind

    /// Returns the links of `markdown`, in order, leaving out those inside code and those to the web.
    ///
    /// Read byte by byte, in one pass: 5,000 notes take a fraction of a second.
    static func links(in markdown: String) -> [NoteLink] {
        let bytes = Array(markdown.utf8)
        let (newline, backtick, tilde, open, close, openParen, closeParen) =
            (UInt8(ascii: "\n"), UInt8(ascii: "`"), UInt8(ascii: "~"), UInt8(ascii: "["), UInt8(ascii: "]"),
             UInt8(ascii: "("), UInt8(ascii: ")"))
        func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        /// The first index from `start` holding `byte` on the same line.
        func find(_ byte: UInt8, from start: Int) -> Int? {
            var index = start
            while index < bytes.count, bytes[index] != newline {
                if bytes[index] == byte { return index }
                index += 1
            }
            return nil
        }
        var links: [NoteLink] = []
        var isInFence = false
        var index = 0
        var isLineStart = true
        while index < bytes.count {
            let byte = bytes[index]
            if isLineStart {
                isLineStart = false
                var first = index
                while first < bytes.count, bytes[first] == UInt8(ascii: " ") || bytes[first] == UInt8(ascii: "\t") {
                    first += 1
                }
                let fence = bytes[first..<min(first + 3, bytes.count)]
                let isFence = fence.count == 3 && (fence.allSatisfy { $0 == backtick } || fence.allSatisfy { $0 == tilde })
                if isFence { isInFence.toggle() }
                if isFence || isInFence {
                    index = (bytes[index...].firstIndex(of: newline) ?? bytes.count) + 1
                    isLineStart = true
                    continue
                }
            }
            switch byte {
            case newline:
                isLineStart = true
            case backtick:
                // Inline code, up to its closing backtick on the same line.
                if let end = find(backtick, from: index + 1) { index = end }
            case open where index + 1 < bytes.count && bytes[index + 1] == open:
                var end = index + 2
                while end + 1 < bytes.count, bytes[end] != newline, bytes[end] != open,
                      !(bytes[end] == close && bytes[end + 1] == close) {
                    end += 1
                }
                if end + 1 < bytes.count, bytes[end] == close, bytes[end + 1] == close {
                    if let citation = NoteCitation(wikilink: text(index + 2..<end)) {
                        links.append(NoteLink(target: citation.note, kind: .wikilink))
                    }
                    index = end + 1
                } else {
                    index = end - 1
                }
            case close where index + 1 < bytes.count && bytes[index + 1] == openParen:
                let start = index + 2
                if start < bytes.count, bytes[start] == UInt8(ascii: "<"), let end = find(UInt8(ascii: ">"), from: start) {
                    if let link = relative(text(start + 1..<end)) { links.append(link) }
                    index = end
                } else if let end = find(closeParen, from: start) {
                    let destination = text(start..<end).split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                    if let link = relative(destination) { links.append(link) }
                    index = end
                }
            default:
                break
            }
            index += 1
        }
        return links
    }

    /// The link to the note at `destination`, as a Markdown link writes it; `nil` for the web, a mail, an anchor in
    /// the same note or a file that is not a note.
    private static func relative(_ destination: String) -> NoteLink? {
        guard !destination.contains(":"), !destination.hasPrefix("#") else { return nil }
        let path = String(destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let decoded = path.removingPercentEncoding ?? path
        let name = decoded.split(separator: "/").last ?? ""
        guard !decoded.isEmpty, !name.contains(".") || name.lowercased().hasSuffix(".md") else { return nil }
        return NoteLink(target: decoded, kind: .relative)
    }
}

/// Finds the note a ``NoteLink`` points to among the notes of a Secondo cervello, as Obsidian does.
nonisolated struct NoteLinkResolver: Sendable {
    /// The notes' paths from the top of the Secondo cervello, lowercased and without `.md`, by index.
    private var indexByPath: [String: Int] = [:]
    /// The notes with each name, lowercased and without `.md`.
    private var indicesByName: [String: [Int]] = [:]
    private let paths: [String]

    /// Creates the resolver of the notes at `paths`, relative to the Secondo cervello, each found by its index.
    init(paths: [String]) {
        self.paths = paths
        for (index, path) in paths.enumerated() {
            let key = Self.key(path)
            indexByPath[key] = indexByPath[key] ?? index
            indicesByName[String(key.split(separator: "/").last ?? ""), default: []].append(index)
        }
    }

    /// The index of the note `link` points to from the note at `source`; `nil` when there is no such note.
    ///
    /// A name alone goes to the note with that name in `source`'s folder, else to the one nearest to the top; a path
    /// goes to that note, or to the one whose path ends with it.
    func note(linkedBy link: NoteLink, from source: String) -> Int? {
        let folder = source.split(separator: "/").dropLast().joined(separator: "/")
        switch link.kind {
        case .relative:
            let fromFolder = Self.normalized(folder.isEmpty ? link.target : folder + "/" + link.target)
            return [fromFolder, Self.normalized(link.target)].lazy.compactMap { $0.flatMap { indexByPath[Self.key($0)] } }
                .first
        case .wikilink:
            let target = Self.key(link.target)
            let name = String(target.split(separator: "/").last ?? "")
            let candidates = (indicesByName[name] ?? []).filter { !target.contains("/") || Self.key(paths[$0]).hasSuffix("/" + target) }
            if !target.contains("/"),
               let sameFolder = candidates.first(where: { paths[$0].split(separator: "/").dropLast().joined(separator: "/") == folder }) {
                return sameFolder
            }
            return indexByPath[target] ?? candidates.min { lhs, rhs in
                let (left, right) = (paths[lhs].split(separator: "/").count, paths[rhs].split(separator: "/").count)
                return left == right ? paths[lhs] < paths[rhs] : left < right
            }
        }
    }

    /// `path` lowercased and without `.md`.
    private static func key(_ path: String) -> String {
        let lowered = path.lowercased()
        return lowered.hasSuffix(".md") ? String(lowered.dropLast(3)) : lowered
    }

    /// `path` without `.` and `..`; `nil` when it leaves the Secondo cervello.
    private static func normalized(_ path: String) -> String? {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." {
                guard parts.popLast() != nil else { return nil }
            } else {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }
}
