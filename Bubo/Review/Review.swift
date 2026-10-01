import Foundation

/// The revisione of a Sessione's changes, blocco by blocco: the files, their blocchi in order, and the rows of the
/// continuous diff, one line or two side by side. The user's decisions are kept apart, in the Sessione.
nonisolated struct Review: Sendable {
    /// A row of the continuous diff: a file's title, a blocco's header, one of its lines or one of its pairs.
    nonisolated struct Row: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case file(Int)
            case hunk(file: Int, hunk: Int)
            case line(file: Int, hunk: Int, line: Int)
            case pair(file: Int, hunk: Int, pair: Int)
        }

        /// The row's position.
        let id: Int
        let kind: Kind
    }

    let files: [ChangedFile]
    /// Every blocco id, in the order of the files.
    let hunkIDs: [String]
    /// The rows of the continuous diff, in order.
    let rows: [Row]
    /// The rows of the side-by-side diff, in order: lines in pairs, before and after.
    let sideBySideRows: [Row]
    /// Where each blocco is: its file and its index in the file, and the row of its header in each diff.
    private let places: [String: (file: Int, hunk: Int, row: Int, sideBySideRow: Int)]

    init(files: [ChangedFile] = []) {
        self.files = files
        var hunkIDs: [String] = []
        var rows: [Row] = []
        var sideBySideRows: [Row] = []
        var places: [String: (file: Int, hunk: Int, row: Int, sideBySideRow: Int)] = [:]
        for (fileIndex, file) in files.enumerated() {
            rows.append(Row(id: rows.count, kind: .file(fileIndex)))
            sideBySideRows.append(Row(id: sideBySideRows.count, kind: .file(fileIndex)))
            for (hunkIndex, hunk) in file.hunks.enumerated() {
                hunkIDs.append(hunk.id)
                places[hunk.id] = (fileIndex, hunkIndex, rows.count, sideBySideRows.count)
                rows.append(Row(id: rows.count, kind: .hunk(file: fileIndex, hunk: hunkIndex)))
                sideBySideRows.append(Row(id: sideBySideRows.count, kind: .hunk(file: fileIndex, hunk: hunkIndex)))
                for lineIndex in hunk.lines.indices {
                    rows.append(Row(id: rows.count, kind: .line(file: fileIndex, hunk: hunkIndex, line: lineIndex)))
                }
                for pairIndex in hunk.pairs.indices {
                    sideBySideRows.append(Row(id: sideBySideRows.count,
                                              kind: .pair(file: fileIndex, hunk: hunkIndex, pair: pairIndex)))
                }
            }
        }
        self.hunkIDs = hunkIDs
        self.rows = rows
        self.sideBySideRows = sideBySideRows
        self.places = places
    }

    /// The blocco `id` with its file; `nil` when the diff no longer has it.
    func hunk(_ id: String) -> (file: ChangedFile, hunk: Hunk)? {
        guard let place = places[id] else { return nil }
        let file = files[place.file]
        return (file, file.hunks[place.hunk])
    }

    /// The index of the file of the blocco `id`.
    func fileIndex(of id: String) -> Int? {
        places[id]?.file
    }

    /// The row of the header of the blocco `id` in the continuous diff.
    func row(of id: String) -> Int? {
        places[id]?.row
    }

    /// The row of the header of the blocco `id` in the side-by-side diff.
    func sideBySideRow(of id: String) -> Int? {
        places[id]?.sideBySideRow
    }

    /// The blocco `offset` places from `id`, stopping at the first and the last; the first blocco without `id`.
    func hunk(movingBy offset: Int, from id: String?) -> String? {
        guard let id, let index = hunkIDs.firstIndex(of: id) else { return hunkIDs.first }
        return hunkIDs[min(max(index + offset, 0), hunkIDs.count - 1)]
    }

    /// The first undecided blocco after `id`, starting again from the top; `id` itself when every blocco is decided.
    func nextUndecided(after id: String, in decisions: [String: HunkDecision]) -> String {
        let start = (hunkIDs.firstIndex(of: id) ?? -1) + 1
        return (hunkIDs[start...] + hunkIDs[..<min(start, hunkIDs.count)])
            .first { decisions[$0] == nil } ?? id
    }

    /// How many blocchi have a decision.
    func decidedCount(in decisions: [String: HunkDecision]) -> Int {
        hunkIDs.count { decisions[$0] != nil }
    }

    /// Whether every blocco is decided and at least one rejected: the rejected ones can go back to the agent.
    func canSendBack(with decisions: [String: HunkDecision]) -> Bool {
        decidedCount(in: decisions) == hunkIDs.count && hunkIDs.contains { decisions[$0] != .accepted }
    }

    /// The new turn that sends the rejected blocchi back to the agent, each with its lines and its note.
    func feedback(for decisions: [String: HunkDecision]) -> String {
        var text = String(localized: "Ho rivisto le tue modifiche e ho rifiutato i blocchi qui sotto. Sono ancora nei file: rifalli seguendo le note, o toglili se non servono. Gli altri blocchi sono approvati: non toccarli.")
        for file in files {
            for hunk in file.hunks {
                guard case let .rejected(note) = decisions[hunk.id] else { continue }
                text += "\n\n" + String(localized: "\(file.path), blocco \(hunk.header):")
                if !hunk.lines.isEmpty {
                    text += "\n```diff\n" + hunk.lines.map { line in
                        switch line.kind {
                        case .context: " " + line.text
                        case .added: "+" + line.text
                        case .removed: "-" + line.text
                        }
                    }.joined(separator: "\n") + "\n```"
                }
                if let note, !note.isEmpty { text += "\n" + String(localized: "Nota: \(note)") }
            }
        }
        return text
    }
}
