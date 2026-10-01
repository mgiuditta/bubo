import Foundation

/// A write the agent asked for, with why: the summary of the Sessione when it asked.
nonisolated struct EditNote: Codable, Equatable, Sendable {
    /// The absolute path of the file written.
    var file: String
    var why: String
    /// The lines written, trimmed, unique, at most 100.
    var lines: [String]
}

nonisolated extension Session {
    /// How many writes a Sessione remembers: the oldest go first.
    static let editNoteLimit = 200

    /// Why the agent wrote `hunk` in the file at `path`: the latest write of the file with one of the blocco's
    /// added lines, or else the latest write of the file. `nil` when the agent did not say.
    func reason(for hunk: Hunk, inFileAt path: String) -> String? {
        let notes = edits.filter { $0.file == path || $0.file.hasSuffix("/" + path) }
        let added = Set(hunk.lines.lazy.filter { $0.kind == .added }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return (notes.last { !added.isDisjoint(with: $0.lines) } ?? notes.last)?.why
    }
}
