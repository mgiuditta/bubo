import Foundation

/// The size and modification time of a file, which tell the Indice whether to read it again.
nonisolated struct FileStamp: Equatable, Sendable {
    /// The size in bytes.
    var size: Int
    /// The modification time, in seconds since 1970.
    var modified: Double

    /// Creates the stamp of a file of `size` bytes modified at `modified`.
    init(size: Int, modified: Double) {
        self.size = size
        self.modified = modified
    }

    /// The stamp of the regular file at `path`; `nil` for a link, a folder or a missing file.
    init?(ofFileAt path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        self.init(info)
    }

    /// The stamp of the file `info` describes; `nil` unless it is a regular file.
    init?(_ info: stat) {
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        size = Int(info.st_size)
        modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
    }
}

/// Which files of the Secondo cervello the Indice reads: `.md` and `.txt` notes, outside hidden folders
/// and the Riassunti di Sessione.
///
/// Links are never followed, so nothing outside the chosen folder is read.
nonisolated enum SecondBrainNotes {
    /// Notes larger than this are left out: a Markdown note is far smaller, a log saved as `.txt` is not.
    static let maximumSize = 8 << 20

    /// Whether the Indice leaves out everything at `relativePath`, relative to the Secondo cervello: hidden files
    /// and folders, as `.obsidian/` and `.trash/`, `Bubo/Sessioni/`, whose Riassunti repeat conversations, and
    /// `excludedFolders` with all they hold.
    ///
    /// The rest of `Bubo/` is read: `Bubo/Note/` and `Bubo/Riunioni/` are sources, not summaries of the Indice.
    ///
    /// Folders compare by whole names: excluding `Archivio` leaves `Archivio2` in.
    static func skips(_ relativePath: String, excluding excludedFolders: Set<String> = []) -> Bool {
        let parts = relativePath.split(separator: "/")
        return parts.contains { $0.hasPrefix(".") } || parts.starts(with: ["Bubo", "Sessioni"] as [Substring])
            || excludedFolders.contains { parts.starts(with: $0.split(separator: "/")) }
    }

    /// Whether a file named `name` is a note.
    static func isNote(named name: String) -> Bool {
        let fileExtension = name.split(separator: ".", omittingEmptySubsequences: false).last?.lowercased()
        return name.contains(".") && (fileExtension == "md" || fileExtension == "txt")
    }

    /// Returns the notes at or under `path`, inside the Secondo cervello at `folder`, outside `excludedFolders`, and
    /// the notes the Indice keeps as they are because iCloud Drive left only their placeholder on the Mac.
    ///
    /// Reading a placeholder would download it: a folder in iCloud Drive is never downloaded by the Indice.
    static func files(at path: String, in folder: String,
                      excluding excludedFolders: Set<String> = []) -> (notes: [String: FileStamp], kept: Set<String>) {
        var notes: [String: FileStamp] = [:]
        var kept: Set<String> = []
        func add(_ file: String) {
            var info = stat()
            guard isNote(named: file), lstat(file, &info) == 0 else { return }
            if info.st_flags & UInt32(SF_DATALESS) != 0 {
                kept.insert(file)
            } else if let stamp = FileStamp(info), stamp.size <= maximumSize {
                notes[file] = stamp
            }
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { return (notes, kept) }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            add(path)
            return (notes, kept)
        }
        let relativeFolder = path == folder ? "" : String(path.dropFirst(folder.count + 1)) + "/"
        guard let entries = FileManager.default.enumerator(atPath: path) else { return (notes, kept) }
        for case let entry as String in entries {
            if skips(relativeFolder + entry, excluding: excludedFolders) {
                // Only for a folder: on a file it would skip the rest of the folder holding it.
                if entries.fileAttributes?[.type] as? FileAttributeType == .typeDirectory { entries.skipDescendants() }
            } else {
                add(path + "/" + entry)
            }
        }
        return (notes, kept)
    }
}
