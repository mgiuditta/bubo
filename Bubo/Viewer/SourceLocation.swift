import Foundation

/// A point in a file: the file, its line and, when known, its column (spec 15).
nonisolated struct SourceLocation: Equatable, Sendable {
    /// The file, as an absolute file URL.
    var file: URL
    /// The line, from 1.
    var line: Int
    /// The column, from 1; `nil` when the location names only the line.
    var column: Int?

    /// Creates the location at `line` and `column` of `file`.
    init(file: URL, line: Int = 1, column: Int? = nil) {
        self.file = file
        self.line = max(line, 1)
        self.column = column.map { max($0, 1) }
    }

    /// Creates the location a terminal link names, `path[:line[:column]]`, with a relative path resolved against
    /// `folder` and `~` expanded; `nil` when the link is a URL with a scheme, such as `http://localhost:3000`.
    ///
    /// The file may not exist: the caller checks before opening it.
    init?(link: String, relativeTo folder: URL) {
        var path = Substring(link)
        var line = 1
        var column: Int?
        if let match = path.wholeMatch(of: /(.+?):(\d+)(?::(\d+))?/) {
            path = match.1
            line = Int(match.2) ?? 1
            column = match.3.flatMap { Int($0) }
        }
        guard !path.isEmpty, URL(string: String(path))?.scheme == nil else { return nil }
        let expanded = NSString(string: String(path)).expandingTildeInPath
        let file = expanded.hasPrefix("/") ? URL(filePath: expanded) : folder.appending(path: expanded)
        self.init(file: file.standardizedFileURL, line: line, column: column)
    }

    /// Whether the location names a regular file that exists, not a folder.
    var isExistingFile: Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder) && !isFolder.boolValue
    }
}
