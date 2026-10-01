import Foundation

/// A file a Sessione changed, with its blocchi.
nonisolated struct ChangedFile: Identifiable, Equatable, Sendable {
    /// The path in the Sessione's folder; for a deleted file, where it was.
    var path: String
    /// Where the file was before a rename; `nil` when it was not renamed.
    var oldPath: String?
    /// Whether git shows the file as binary, without lines.
    var isBinary = false
    /// The blocchi, in the file's order; never empty.
    var hunks: [Hunk] = []

    var id: String { path }
}

nonisolated extension ChangedFile {
    /// The files of `diff`, the output of `git diff`, in its order.
    static func files(in diff: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        var file: ChangedFile?
        /// The lines between `diff --git` and the first blocco, such as `index` and `rename from`.
        var details: [String] = []
        var removedPath: String?
        var header: String?
        var lines: [Hunk.Line] = []

        func endHunk() {
            guard var current = file, let hunkHeader = header else { return }
            current.hunks.append(uniqueHunk(in: current, header: hunkHeader, lines: lines))
            file = current
            header = nil
            lines = []
        }
        func endFile() {
            endHunk()
            guard var current = file else { return }
            if current.hunks.isEmpty {
                current.hunks = [uniqueHunk(in: current, header: details.joined(separator: "\n"), lines: [])]
            }
            files.append(current)
            file = nil
            details = []
            removedPath = nil
        }

        for slice in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if slice.hasPrefix("diff --git ") {
                endFile()
                // `a/x b/y`: the path after the last ` b/`, until `+++` or `rename to` says it exactly.
                let range = slice.range(of: " b/", options: .backwards)
                file = ChangedFile(path: range.map { String(slice[$0.upperBound...]) } ?? String(slice))
                continue
            }
            guard file != nil else { continue }
            if header != nil {
                switch slice.first {
                case "@": endHunk(); header = String(slice)
                case "+": lines.append(Hunk.Line(kind: .added, text: String(slice.dropFirst())))
                case "-": lines.append(Hunk.Line(kind: .removed, text: String(slice.dropFirst())))
                case " ": lines.append(Hunk.Line(kind: .context, text: String(slice.dropFirst())))
                default: break // `\ No newline at end of file`, or the empty end of the output
                }
            } else if slice.hasPrefix("@@") {
                header = String(slice)
            } else if slice.hasPrefix("--- ") {
                removedPath = slice.hasPrefix("--- a/") ? String(slice.dropFirst(6)) : nil
            } else if slice.hasPrefix("+++ ") {
                if slice.hasPrefix("+++ b/") { file?.path = String(slice.dropFirst(6)) }
                else if let removedPath { file?.path = removedPath }
            } else {
                details.append(String(slice))
                if slice.hasPrefix("rename from ") { file?.oldPath = String(slice.dropFirst(12)) }
                if slice.hasPrefix("rename to ") { file?.path = String(slice.dropFirst(10)) }
                if slice.hasPrefix("Binary files ") { file?.isBinary = true }
            }
        }
        endFile()
        return files
    }

    /// The blocco `header` with `lines` in `file`, with an id no other blocco of the file has.
    private static func uniqueHunk(in file: ChangedFile, header: String, lines: [Hunk.Line]) -> Hunk {
        var occurrence = 0
        while true {
            let hunk = Hunk(path: file.path, header: header, lines: lines, occurrence: occurrence)
            if !file.hunks.contains(where: { $0.id == hunk.id }) { return hunk }
            occurrence += 1
        }
    }
}
